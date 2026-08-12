defmodule PaperForge.Protection do
  @moduledoc """
  Document-level protection policies independent from password encryption.

  Protection can add watermarks and tamper-evident metadata, and can reject
  links or attachments that exceed an application's resource policy.
  """

  alias PaperForge.Document
  alias PaperForge.Reference
  alias PaperForge.Stream

  @default_policy [
    allowed_uri_schemes: ["https", "mailto"],
    allowed_hosts: :any,
    allow_attachments: true,
    max_attachments: 20,
    max_attachment_bytes: 10_000_000,
    allowed_attachment_mimes: :any
  ]

  @type issue :: %{code: atom(), message: binary(), object_id: pos_integer()}

  @doc "Applies watermark, audit policy, unique identifier, and fingerprint options."
  @spec apply(Document.t(), keyword()) :: Document.t()
  def apply(%Document{} = document, options) when is_list(options) do
    document =
      case Keyword.get(options, :watermark) do
        nil ->
          document

        watermark when is_list(watermark) ->
          watermark(document, watermark)

        text when is_binary(text) ->
          watermark(document, text: text)

        other ->
          raise ArgumentError, "watermark must be text or a keyword list, got: #{inspect(other)}"
      end

    policy = Keyword.get(options, :policy, [])

    case audit(document, policy) do
      {:ok, _report} -> stamp(document, options)
      {:error, issues} -> raise ArgumentError, format_issues(issues)
    end
  end

  @doc "Adds a centered text watermark to every page."
  @spec watermark(Document.t(), keyword()) :: Document.t()
  def watermark(%Document{} = document, options) when is_list(options) do
    text = Keyword.fetch!(options, :text)
    opacity = Keyword.get(options, :opacity, 0.14)
    size = Keyword.get(options, :size, 54)
    color = Keyword.get(options, :color, {0.45, 0.48, 0.52})
    angle = Keyword.get(options, :angle, 35)

    unless is_binary(text) and text != "",
      do: raise(ArgumentError, "watermark text cannot be empty")

    unless opacity >= 0 and opacity <= 1,
      do: raise(ArgumentError, "watermark opacity must be 0..1")

    {document, font_ref} =
      Document.add_object(document, %{
        "Type" => {:name, "Font"},
        "Subtype" => {:name, "Type1"},
        "BaseFont" => {:name, "Helvetica-Bold"},
        "Encoding" => {:name, "WinAnsiEncoding"}
      })

    {document, state_ref} =
      Document.add_object(document, %{
        "Type" => {:name, "ExtGState"},
        "ca" => opacity,
        "CA" => opacity
      })

    Enum.reduce(page_references(document), document, fn page_ref, current ->
      page = Document.fetch_object!(current, page_ref).value
      [_, _, width, height] = Map.fetch!(page, "MediaBox")
      command = watermark_command(text, width, height, size, angle, color)
      filters = if current.compress, do: [:flate], else: []
      {current, stream_ref} = Document.add_object(current, Stream.new(command, filters: filters))

      Document.update_object(current, page_ref, fn dictionary ->
        resources = Map.get(dictionary, "Resources", %{})

        resources =
          resources
          |> Map.update(
            "Font",
            %{"PFWatermark" => font_ref},
            &Map.put(&1, "PFWatermark", font_ref)
          )
          |> Map.update(
            "ExtGState",
            %{"PFWatermarkGS" => state_ref},
            &Map.put(&1, "PFWatermarkGS", state_ref)
          )

        contents =
          case Map.get(dictionary, "Contents") do
            list when is_list(list) -> list ++ [stream_ref]
            %Reference{} = reference -> [reference, stream_ref]
            nil -> [stream_ref]
          end

        dictionary
        |> Map.put("Resources", resources)
        |> Map.put("Contents", contents)
      end)
    end)
  end

  @doc "Returns a stable SHA-256 fingerprint of the document's semantic PDF objects."
  @spec fingerprint(Document.t()) :: binary()
  def fingerprint(%Document{} = document) do
    document.objects
    |> Map.new(fn {id, object} -> {id, normalize_for_fingerprint(object.value)} end)
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "Checks a document against its embedded PaperForge fingerprint."
  @spec verify_fingerprint(Document.t()) :: :ok | {:error, :missing_fingerprint | :modified}
  def verify_fingerprint(%Document{} = document) do
    catalog = Document.fetch_object!(document, document.root_reference).value

    case get_in(catalog, ["PieceInfo", "PaperForge", "Private", "Fingerprint"]) do
      nil ->
        {:error, :missing_fingerprint}

      expected ->
        if secure_compare(expected, fingerprint(document)), do: :ok, else: {:error, :modified}
    end
  end

  @doc "Audits links and embedded files without mutating the document."
  @spec audit(Document.t(), keyword()) :: {:ok, map()} | {:error, [issue()]}
  def audit(%Document{} = document, options \\ []) when is_list(options) do
    policy = Keyword.merge(@default_policy, options)

    {issues, attachments, links, bytes} =
      Enum.reduce(document.objects, {[], 0, 0, 0}, fn {id, object}, acc ->
        audit_value(object.value, id, policy, acc)
      end)

    issues =
      if attachments > policy[:max_attachments] do
        [
          %{
            code: :too_many_attachments,
            message: "attachment count exceeds #{policy[:max_attachments]}",
            object_id: document.root_reference.object_id
          }
          | issues
        ]
      else
        issues
      end

    report = %{attachments: attachments, attachment_bytes: bytes, links: links, policy: policy}
    if issues == [], do: {:ok, report}, else: {:error, Enum.reverse(issues)}
  end

  defp stamp(document, options) do
    identifier = Keyword.get_lazy(options, :identifier, fn -> unique_identifier(document) end)

    document =
      Document.update_object(document, document.root_reference, fn catalog ->
        Map.put(catalog, "PieceInfo", %{
          "PaperForge" => %{
            "LastModified" => Keyword.get(options, :modified_at, "D:19700101000000Z"),
            "Private" => %{"Identifier" => identifier}
          }
        })
      end)

    digest = fingerprint(document)

    Document.update_object(document, document.root_reference, fn catalog ->
      put_in(catalog, ["PieceInfo", "PaperForge", "Private", "Fingerprint"], digest)
    end)
  end

  defp unique_identifier(document) do
    "urn:uuid:" <> (fingerprint(document) |> binary_part(0, 32) |> format_uuid())
  end

  defp format_uuid(<<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>>),
    do: Enum.join([a, b, c, d, e], "-")

  defp watermark_command(text, width, height, size, angle, {red, green, blue}) do
    radians = angle * :math.pi() / 180
    cosine = Float.round(:math.cos(radians), 6)
    sine = Float.round(:math.sin(radians), 6)
    estimated_width = String.length(text) * size * 0.55

    IO.iodata_to_binary([
      "/Artifact BMC\nq\n/PFWatermarkGS gs\n",
      number(red),
      " ",
      number(green),
      " ",
      number(blue),
      " rg\n",
      "BT\n/PFWatermark ",
      number(size),
      " Tf\n",
      number(cosine),
      " ",
      number(sine),
      " ",
      number(-sine),
      " ",
      number(cosine),
      " ",
      number(width / 2 - estimated_width / 2),
      " ",
      number(height / 2),
      " Tm\n",
      "(",
      escape(text),
      ") Tj\nET\nQ\nEMC"
    ])
  end

  defp audit_value(%Stream{dictionary: dictionary, data: data}, id, policy, acc) do
    {issues, attachments, links, bytes} = audit_value(dictionary, id, policy, acc)

    if dictionary["Type"] == {:name, "EmbeddedFile"} do
      mime = dictionary["Subtype"]
      issues = attachment_issues(id, byte_size(data), mime, policy) ++ issues
      {issues, attachments + 1, links, bytes + byte_size(data)}
    else
      {issues, attachments, links, bytes}
    end
  end

  defp audit_value(%Reference{}, _id, _policy, acc), do: acc

  defp audit_value(value, id, policy, acc) when is_map(value) do
    acc =
      case Map.get(value, "URI") do
        uri when is_binary(uri) -> audit_uri(uri, id, policy, acc)
        _ -> acc
      end

    Enum.reduce(value, acc, fn {_key, child}, current ->
      audit_value(child, id, policy, current)
    end)
  end

  defp audit_value(value, id, policy, acc) when is_list(value),
    do: Enum.reduce(value, acc, &audit_value(&1, id, policy, &2))

  defp audit_value(_value, _id, _policy, acc), do: acc

  defp audit_uri(uri, id, policy, {issues, attachments, links, bytes}) do
    parsed = URI.parse(uri)
    scheme_allowed = parsed.scheme in policy[:allowed_uri_schemes]
    host_allowed = policy[:allowed_hosts] == :any or parsed.host in policy[:allowed_hosts]

    issue =
      cond do
        not scheme_allowed ->
          %{
            code: :uri_scheme_denied,
            message: "URI scheme is not allowed: #{inspect(parsed.scheme)}",
            object_id: id
          }

        not host_allowed ->
          %{
            code: :uri_host_denied,
            message: "URI host is not allowed: #{inspect(parsed.host)}",
            object_id: id
          }

        true ->
          nil
      end

    {if(issue, do: [issue | issues], else: issues), attachments, links + 1, bytes}
  end

  defp attachment_issues(id, size, mime, policy) do
    []
    |> maybe_issue(
      not policy[:allow_attachments],
      :attachments_denied,
      "attachments are disabled",
      id
    )
    |> maybe_issue(
      size > policy[:max_attachment_bytes],
      :attachment_too_large,
      "attachment exceeds #{policy[:max_attachment_bytes]} bytes",
      id
    )
    |> maybe_issue(
      policy[:allowed_attachment_mimes] != :any and mime not in policy[:allowed_attachment_mimes],
      :attachment_mime_denied,
      "attachment MIME type is not allowed: #{inspect(mime)}",
      id
    )
  end

  defp maybe_issue(issues, true, code, message, id),
    do: [%{code: code, message: message, object_id: id} | issues]

  defp maybe_issue(issues, false, _code, _message, _id), do: issues

  defp normalize_for_fingerprint(%Reference{} = value), do: value

  defp normalize_for_fingerprint(%Stream{} = value) do
    %{value | dictionary: normalize_for_fingerprint(value.dictionary)}
  end

  defp normalize_for_fingerprint(value) when is_map(value) do
    value
    |> Map.delete("PieceInfo")
    |> Map.new(fn {key, child} -> {key, normalize_for_fingerprint(child)} end)
  end

  defp normalize_for_fingerprint(value) when is_list(value),
    do: Enum.map(value, &normalize_for_fingerprint/1)

  defp normalize_for_fingerprint(value), do: value

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :crypto.exor(right)
    |> :binary.bin_to_list()
    |> Enum.reduce(0, &Bitwise.bor/2)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false

  defp format_issues(issues),
    do: "document protection policy failed: " <> Enum.map_join(issues, "; ", & &1.message)

  defp escape(text),
    do:
      text
      |> String.replace("\\", "\\\\")
      |> String.replace("(", "\\(")
      |> String.replace(")", "\\)")

  defp number(value) when is_integer(value), do: Integer.to_string(value)

  defp number(value),
    do:
      value
      |> Float.round(4)
      |> :erlang.float_to_binary(decimals: 4)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")

  defp page_references(document),
    do: Document.fetch_object!(document, document.pages_reference).value["Kids"]
end
