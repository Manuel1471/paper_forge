defmodule PaperForge.Compliance do
  @moduledoc """
  Structural PDF/A and PDF/UA preparation with deterministic validation reports.

  PaperForge validates the requirements it emits. Final archival certification
  should also be performed with VeraPDF because conformance includes rules that
  depend on the complete rendered document and the selected ICC profile.
  """

  alias PaperForge.Document
  alias PaperForge.Reference
  alias PaperForge.Stream

  @profiles [:pdf_a_2b, :pdf_a_3b, :pdf_ua_1]

  @type issue :: %{code: atom(), message: binary(), path: binary()}

  @doc "Applies one or more conformance profiles to a document."
  @spec apply(Document.t(), keyword()) :: Document.t()
  def apply(%Document{} = document, options) when is_list(options) do
    profiles = options |> Keyword.get(:profiles, []) |> List.wrap()
    validate_profiles!(profiles)

    document = if :pdf_ua_1 in profiles, do: tag_document(document, options), else: document

    document =
      if Enum.any?(profiles, &(&1 in [:pdf_a_2b, :pdf_a_3b])),
        do: add_output_intent(document, options),
        else: document

    document = add_xmp(document, profiles, options)

    case validate(document, profiles: profiles, security: Keyword.get(options, :security)) do
      {:ok, _report} -> document
      {:error, issues} -> raise ArgumentError, format_issues(issues)
    end
  end

  @doc "Returns a machine-readable conformance report."
  @spec validate(Document.t(), keyword()) :: {:ok, map()} | {:error, [issue()]}
  def validate(%Document{} = document, options) when is_list(options) do
    profiles = options |> Keyword.get(:profiles, []) |> List.wrap()
    validate_profiles!(profiles)
    catalog = Document.fetch_object!(document, document.root_reference).value

    issues =
      []
      |> require_metadata(document, profiles)
      |> require_xmp(catalog, profiles)
      |> require_pdf_ua(catalog, profiles)
      |> require_pdf_a(catalog, profiles, options)

    report = %{
      profiles: profiles,
      pages: page_references(document) |> length(),
      tagged: get_in(catalog, ["MarkInfo", "Marked"]) == true,
      language: catalog["Lang"],
      output_intent: Map.has_key?(catalog, "OutputIntents")
    }

    if issues == [], do: {:ok, report}, else: {:error, Enum.reverse(issues)}
  end

  @doc "Associates alternate text with an image XObject for tagged-document tooling."
  @spec alternate_text(Document.t(), Reference.t(), binary()) :: Document.t()
  def alternate_text(%Document{} = document, %Reference{} = image_reference, text)
      when is_binary(text) and text != "" do
    Document.update_object(document, image_reference, fn
      %Stream{} = stream ->
        Stream.put(stream, "Alt", text)

      other ->
        raise ArgumentError,
              "alternate text target must be an image stream, got: #{inspect(other)}"
    end)
  end

  defp tag_document(document, options) do
    language = Keyword.get(options, :language, "en-US")
    title = Keyword.get(options, :title) || metadata_title(document)

    if not is_binary(language) or language == "",
      do: raise(ArgumentError, "PDF/UA requires a document language")

    if not is_binary(title) or title == "",
      do: raise(ArgumentError, "PDF/UA requires a document title")

    pages = page_references(document)
    {document, parent_tree_ref} = Document.add_object(document, %{"Nums" => []})

    {document, struct_root_ref} =
      Document.add_object(document, %{
        "Type" => {:name, "StructTreeRoot"},
        "K" => [],
        "ParentTree" => parent_tree_ref,
        "ParentTreeNextKey" => length(pages),
        "RoleMap" => %{"Document" => {:name, "Document"}, "P" => {:name, "P"}}
      })

    {document, document_element_ref} =
      Document.add_object(document, %{
        "Type" => {:name, "StructElem"},
        "S" => {:name, "Document"},
        "P" => struct_root_ref,
        "K" => []
      })

    {document, element_refs} =
      pages
      |> Enum.with_index()
      |> Enum.reduce({document, []}, fn {page_ref, index}, {current, refs} ->
        current = tag_page_contents(current, page_ref)

        {current, element_ref} =
          Document.add_object(current, %{
            "Type" => {:name, "StructElem"},
            "S" => {:name, "P"},
            "P" => document_element_ref,
            "Pg" => page_ref,
            "K" => 0
          })

        current = Document.update_object(current, page_ref, &Map.put(&1, "StructParents", index))
        {current, refs ++ [element_ref]}
      end)

    nums =
      element_refs |> Enum.with_index() |> Enum.flat_map(fn {ref, index} -> [index, [ref]] end)

    document = Document.update_object(document, parent_tree_ref, &Map.put(&1, "Nums", nums))

    document =
      Document.update_object(document, document_element_ref, &Map.put(&1, "K", element_refs))

    document =
      Document.update_object(document, struct_root_ref, &Map.put(&1, "K", [document_element_ref]))

    Document.update_object(document, document.root_reference, fn catalog ->
      catalog
      |> Map.put("StructTreeRoot", struct_root_ref)
      |> Map.put("MarkInfo", %{"Marked" => true})
      |> Map.put("Lang", language)
      |> Map.put("ViewerPreferences", %{"DisplayDocTitle" => true})
    end)
  end

  defp tag_page_contents(document, page_ref) do
    page = Document.fetch_object!(document, page_ref).value

    page["Contents"]
    |> List.wrap()
    |> Enum.reduce(document, fn
      %Reference{} = content_ref, current ->
        Document.update_object(current, content_ref, fn
          %Stream{} = stream -> %{stream | data: ["/P <</MCID 0>> BDC\n", stream.data, "\nEMC"]}
          other -> other
        end)

      _, current ->
        current
    end)
  end

  defp add_output_intent(document, options) do
    data = load_icc!(Keyword.get(options, :icc_profile))
    validate_icc!(data)
    components = icc_components(data)

    {document, profile_ref} =
      Document.add_object(
        document,
        Stream.new(data, dictionary: %{"N" => components}, filters: [:flate])
      )

    {document, intent_ref} =
      Document.add_object(document, %{
        "Type" => {:name, "OutputIntent"},
        "S" => {:name, "GTS_PDFA1"},
        "OutputConditionIdentifier" => Keyword.get(options, :output_condition, "Custom RGB"),
        "Info" => Keyword.get(options, :output_condition, "Custom RGB"),
        "DestOutputProfile" => profile_ref
      })

    Document.update_object(
      document,
      document.root_reference,
      &Map.put(&1, "OutputIntents", [intent_ref])
    )
  end

  defp add_xmp(document, [], _options), do: document

  defp add_xmp(document, profiles, options) do
    title = Keyword.get(options, :title) || metadata_title(document) || "Untitled"
    xmp = xmp_packet(title, profiles)

    {document, metadata_ref} =
      Document.add_object(
        document,
        Stream.new(xmp,
          dictionary: %{"Type" => {:name, "Metadata"}, "Subtype" => {:name, "XML"}}
        )
      )

    Document.update_object(
      document,
      document.root_reference,
      &Map.put(&1, "Metadata", metadata_ref)
    )
  end

  defp xmp_packet(title, profiles) do
    pdfa =
      cond do
        :pdf_a_3b in profiles ->
          "<pdfaid:part>3</pdfaid:part><pdfaid:conformance>B</pdfaid:conformance>"

        :pdf_a_2b in profiles ->
          "<pdfaid:part>2</pdfaid:part><pdfaid:conformance>B</pdfaid:conformance>"

        true ->
          ""
      end

    pdfua = if :pdf_ua_1 in profiles, do: "<pdfuaid:part>1</pdfuaid:part>", else: ""

    """
    <?xpacket begin='' id='W5M0MpCehiHzreSzNTczkc9d'?>
    <x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'>
    <rdf:Description rdf:about='' xmlns:dc='http://purl.org/dc/elements/1.1/' xmlns:pdfaid='http://www.aiim.org/pdfa/ns/id/' xmlns:pdfuaid='http://www.aiim.org/pdfua/ns/id/'>
    <dc:title><rdf:Alt><rdf:li xml:lang='x-default'>#{xml_escape(title)}</rdf:li></rdf:Alt></dc:title>#{pdfa}#{pdfua}
    </rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end='w'?>
    """
  end

  defp require_metadata(issues, document, profiles) do
    if profiles != [] and is_nil(document.info_reference),
      do: [
        issue(
          :metadata_missing,
          "conformance profiles require an information dictionary",
          "document.info"
        )
        | issues
      ],
      else: issues
  end

  defp require_xmp(issues, catalog, profiles) do
    if profiles != [] and not match?(%Reference{}, catalog["Metadata"]),
      do: [
        issue(:xmp_missing, "conformance profiles require XMP metadata", "catalog.Metadata")
        | issues
      ],
      else: issues
  end

  defp require_pdf_ua(issues, catalog, profiles) do
    if :pdf_ua_1 in profiles do
      issues
      |> maybe_add(
        get_in(catalog, ["MarkInfo", "Marked"]) != true,
        :tagging_missing,
        "PDF/UA requires MarkInfo/Marked",
        "catalog.MarkInfo"
      )
      |> maybe_add(
        not match?(%Reference{}, catalog["StructTreeRoot"]),
        :structure_tree_missing,
        "PDF/UA requires a structure tree",
        "catalog.StructTreeRoot"
      )
      |> maybe_add(
        not is_binary(catalog["Lang"]) or catalog["Lang"] == "",
        :language_missing,
        "PDF/UA requires a language",
        "catalog.Lang"
      )
    else
      issues
    end
  end

  defp require_pdf_a(issues, catalog, profiles, options) do
    if Enum.any?(profiles, &(&1 in [:pdf_a_2b, :pdf_a_3b])) do
      issues
      |> maybe_add(
        not match?([%Reference{}], catalog["OutputIntents"]),
        :output_intent_missing,
        "PDF/A requires an ICC output intent",
        "catalog.OutputIntents"
      )
      |> maybe_add(
        not is_nil(Keyword.get(options, :security)),
        :encryption_forbidden,
        "PDF/A documents cannot be encrypted",
        "write.security"
      )
    else
      issues
    end
  end

  defp metadata_title(%Document{info_reference: nil}), do: nil

  defp metadata_title(document) do
    case Document.fetch_object!(document, document.info_reference).value["Title"] do
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp load_icc!(nil), do: raise(ArgumentError, "PDF/A requires :icc_profile binary or path")

  defp load_icc!(data) when is_binary(data) do
    if File.regular?(data), do: File.read!(data), else: data
  end

  defp validate_icc!(data) when byte_size(data) >= 128 do
    if binary_part(data, 36, 4) != "acsp",
      do: raise(ArgumentError, "invalid ICC profile signature")

    data
  end

  defp validate_icc!(_data),
    do: raise(ArgumentError, "ICC profile must contain a complete 128-byte header")

  defp icc_components(data) do
    case binary_part(data, 16, 4) do
      "GRAY" -> 1
      "RGB " -> 3
      "CMYK" -> 4
      color_space -> raise ArgumentError, "unsupported ICC color space: #{inspect(color_space)}"
    end
  end

  defp validate_profiles!(profiles) do
    case profiles -- @profiles do
      [] -> :ok
      unknown -> raise ArgumentError, "unsupported compliance profiles: #{inspect(unknown)}"
    end
  end

  defp page_references(document),
    do: Document.fetch_object!(document, document.pages_reference).value["Kids"]

  defp issue(code, message, path), do: %{code: code, message: message, path: path}
  defp maybe_add(issues, true, code, message, path), do: [issue(code, message, path) | issues]
  defp maybe_add(issues, false, _code, _message, _path), do: issues

  defp format_issues(issues),
    do: "PDF conformance failed: " <> Enum.map_join(issues, "; ", &"#{&1.path}: #{&1.message}")

  defp xml_escape(value),
    do:
      value
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")
end
