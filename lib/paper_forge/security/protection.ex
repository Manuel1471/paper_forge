defmodule PaperForge.Protection do
  @moduledoc """
  Document-level protection policies independent from password encryption.

  Protection can add watermarks and tamper-evident metadata, and can reject
  links or attachments that exceed an application's resource policy.
  """

  alias PaperForge.Document
  alias PaperForge.Fonts.WinAnsi
  alias PaperForge.PDF.Graph
  alias PaperForge.Reference
  alias PaperForge.Serializer
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

    unless is_number(opacity) and opacity >= 0 and opacity <= 1,
      do: raise(ArgumentError, "watermark opacity must be 0..1")

    margin = Keyword.get(options, :margin, 36)
    fit = Keyword.get(options, :fit, true)
    offset_x = Keyword.get(options, :offset_x, 0)
    offset_y = Keyword.get(options, :offset_y, 0)

    validate_watermark_geometry!(size, angle, margin, fit, offset_x, offset_y)
    validate_watermark_color!(color)

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

    Enum.reduce(Graph.pages!(document), document, fn page, current ->
      watermark_page(
        current,
        page,
        {font_ref, state_ref},
        {text, size, angle, color, margin, fit, offset_x, offset_y}
      )
    end)
  end

  defp watermark_page(
         current,
         page,
         {font_ref, state_ref},
         {text, size, angle, color, margin, fit, offset_x, offset_y}
       ) do
    dictionary = page.dictionary
    box = Graph.resolve!(current, dictionary["CropBox"] || dictionary["MediaBox"])
    [x0, y0, x1, y1] = box
    resources = Graph.resolve!(current, dictionary["Resources"]) || %{}
    fonts = Graph.resolve!(current, resources["Font"]) || %{}
    states = Graph.resolve!(current, resources["ExtGState"]) || %{}
    font_name = unique_name(fonts, "PFWatermark")
    state_name = unique_name(states, "PFWatermarkGS")

    command =
      watermark_command(
        text,
        {x0, y0, x1, y1},
        size,
        angle,
        color,
        {margin, fit, offset_x, offset_y},
        {font_name, state_name}
      )

    filters = if current.compress, do: [:flate], else: []
    {current, before} = Document.add_object(current, Stream.new("q\n"))

    {current, stream_ref} =
      Document.add_object(current, Stream.new("Q\n" <> command, filters: filters))

    contents =
      case Graph.resolve!(current, dictionary["Contents"]) do
        nil -> []
        %Stream{} -> [dictionary["Contents"]]
        list when is_list(list) -> list
      end

    Document.update_object(current, page.reference, fn value ->
      value
      |> Map.put(
        "Resources",
        resources
        |> Map.put("Font", Map.put(fonts, font_name, font_ref))
        |> Map.put("ExtGState", Map.put(states, state_name, state_ref))
      )
      |> Map.put("Contents", [before | contents] ++ [stream_ref])
    end)
  end

  defp validate_watermark_geometry!(size, angle, margin, fit, offset_x, offset_y) do
    valid = Enum.all?([size, angle, margin, offset_x, offset_y], &is_number/1)

    unless valid and size > 0 and margin >= 0 and is_boolean(fit),
      do: raise(ArgumentError, "invalid watermark size, angle, margin, fit or offsets")
  end

  defp validate_watermark_color!({red, green, blue}) do
    unless Enum.all?([red, green, blue], &(is_number(&1) and &1 >= 0 and &1 <= 1)),
      do: raise(ArgumentError, "watermark color must contain three numbers in 0..1")
  end

  defp validate_watermark_color!(_), do: raise(ArgumentError, "invalid watermark color")

  defp unique_name(map, name),
    do: if(Map.has_key?(map, name), do: unique_name(map, name <> "_"), else: name)

  @doc "Returns a stable SHA-256 fingerprint of the document's semantic PDF objects."
  @spec fingerprint(Document.t()) :: binary()
  def fingerprint(%Document{} = document) do
    header =
      Serializer.encode([document.root_reference, document.info_reference, document.pdf_version])

    initial = :crypto.hash_update(:crypto.hash_init(:sha256), header)

    document.objects
    |> Enum.sort_by(fn {id, _} -> id end)
    |> Enum.reduce(initial, fn {id, object}, digest ->
      value =
        if id == document.root_reference.object_id,
          do: omit_fingerprint(object.value),
          else: object.value

      :crypto.hash_update(digest, [
        Integer.to_string(id),
        " ",
        Integer.to_string(object.generation),
        " obj\n",
        value |> canonical_pdf_value() |> Serializer.encode(),
        "\nendobj\n"
      ])
    end)
    |> :crypto.hash_final()
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
        piece_info = Graph.resolve!(document, catalog["PieceInfo"]) || %{}

        Map.put(
          catalog,
          "PieceInfo",
          Map.put(piece_info, "PaperForge", %{
            "LastModified" => Keyword.get(options, :modified_at, "D:19700101000000Z"),
            "Private" => %{"Identifier" => identifier}
          })
        )
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

  defp watermark_command(
         text,
         {x0, y0, x1, y1},
         size,
         angle,
         {red, green, blue},
         {margin, fit, offset_x, offset_y},
         {font_name, state_name}
       ) do
    radians = angle * :math.pi() / 180
    cosine = Float.round(:math.cos(radians), 6)
    sine = Float.round(:math.sin(radians), 6)
    width = PaperForge.TextMetrics.width(text, font: :helvetica_bold, size: size)
    height = size * 0.718
    rotated_width = abs(cosine) * width + abs(sine) * height
    rotated_height = abs(sine) * width + abs(cosine) * height
    available_width = x1 - x0 - 2 * margin - 2 * abs(offset_x)
    available_height = y1 - y0 - 2 * margin - 2 * abs(offset_y)

    if fit and (available_width <= 0 or available_height <= 0),
      do: raise(ArgumentError, "watermark margins and offsets leave no space")

    scale =
      if fit,
        do:
          min(
            1,
            min(
              available_width / rotated_width,
              available_height / rotated_height
            )
          ),
        else: 1

    size = size * scale
    width = width * scale
    height = height * scale
    origin_x = (x0 + x1) / 2 + offset_x - cosine * width / 2 + sine * height / 2
    origin_y = (y0 + y1) / 2 + offset_y - sine * width / 2 - cosine * height / 2

    IO.iodata_to_binary([
      "/Artifact BMC\nq\n/",
      state_name,
      " gs\n",
      number(red),
      " ",
      number(green),
      " ",
      number(blue),
      " rg\n",
      "BT\n/",
      font_name,
      " ",
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
      number(origin_x),
      " ",
      number(origin_y),
      " Tm\n",
      "(",
      escape(WinAnsi.encode!(text, :helvetica_bold)),
      ") Tj\nET\nQ\nEMC"
    ])
  end

  defp audit_value(%Stream{dictionary: dictionary, data: data}, id, policy, acc) do
    {issues, attachments, links, bytes} = audit_value(dictionary, id, policy, acc)

    if dictionary["Type"] == {:name, "EmbeddedFile"} do
      mime =
        case dictionary["Subtype"] do
          {:name, value} -> value
          value -> value
        end

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

  defp canonical_pdf_value({:hex_string, value}), do: value
  defp canonical_pdf_value(%Reference{} = value), do: value

  defp canonical_pdf_value(%Stream{} = stream),
    do: %{stream | dictionary: canonical_pdf_value(stream.dictionary)}

  defp canonical_pdf_value(value) when is_map(value),
    do: Map.new(value, fn {key, child} -> {key, canonical_pdf_value(child)} end)

  defp canonical_pdf_value(value) when is_list(value), do: Enum.map(value, &canonical_pdf_value/1)
  defp canonical_pdf_value(value), do: value

  # Exclude only the checksum itself, not unrelated application metadata.
  defp omit_fingerprint(%{"PieceInfo" => %{"PaperForge" => %{"Private" => private}}} = catalog)
       when is_map(private) do
    put_in(catalog, ["PieceInfo", "PaperForge", "Private"], Map.delete(private, "Fingerprint"))
  end

  defp omit_fingerprint(value), do: value

  defp secure_compare(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
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
end
