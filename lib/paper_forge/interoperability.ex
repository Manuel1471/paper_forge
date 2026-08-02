defmodule PaperForge.Interoperability do
  @moduledoc """
  Imports, composes, and inspects PDF documents without external executables.

  Binary import supports unencrypted PDFs using direct objects and traditional
  page trees. Encrypted PDFs and compressed object streams are rejected with
  structured errors.
  """

  alias PaperForge.{Document, Object, Reference, Stream}
  alias PaperForge.PDF.Parser

  @type source :: Document.t() | binary()

  @doc "Parses a PDF binary into a composable document object graph."
  @spec parse_pdf(binary()) :: {:ok, Document.t()} | {:error, term()}
  def parse_pdf(pdf), do: Parser.parse(pdf)

  @doc "Imports selected one-based pages from a PDF or PaperForge document."
  @spec import_pages(source(), Range.t() | [pos_integer()] | :all, keyword()) ::
          {:ok, Document.t()} | {:error, term()}
  def import_pages(source, pages \\ :all, options \\ []) do
    with {:ok, document} <- normalize_source(source),
         {:ok, selected} <- select_pages(document, pages) do
      target =
        Document.new(
          pdf_version: Keyword.get(options, :pdf_version, document.pdf_version),
          compress: Keyword.get(options, :compress, true)
        )

      {:ok, import_document(target, document, selected) |> deduplicate_resources()}
    end
  end

  @doc "Composes several PDF binaries or documents in order."
  @spec compose([source()], keyword()) :: {:ok, Document.t()} | {:error, term()}
  def compose(sources, options \\ []) when is_list(sources) and sources != [] do
    target =
      Document.new(
        pdf_version: Keyword.get(options, :pdf_version, "1.7"),
        compress: Keyword.get(options, :compress, true)
      )

    sources
    |> Enum.reduce_while({:ok, target}, fn source, {:ok, current} ->
      with {:ok, document} <- normalize_source(source),
           {:ok, pages} <- select_pages(document, :all) do
        {:cont, {:ok, import_document(current, document, pages)}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, document} -> {:ok, deduplicate_resources(document)}
      error -> error
    end
  end

  @doc "Returns reusable font, XObject, embedded-file, and appearance resources."
  @spec resources(Document.t()) :: map()
  def resources(%Document{} = document) do
    Enum.reduce(
      document.objects,
      %{fonts: [], xobjects: [], embedded_files: [], appearances: []},
      fn {id, object}, inventory ->
        case object.value do
          %{"Type" => {:name, "Font"}} ->
            Map.update!(inventory, :fonts, &[Reference.new(id) | &1])

          %Stream{dictionary: %{"Type" => {:name, "XObject"}, "Subtype" => {:name, "Image"}}} ->
            Map.update!(inventory, :xobjects, &[Reference.new(id) | &1])

          %Stream{dictionary: %{"Type" => {:name, "XObject"}, "Subtype" => {:name, "Form"}}} ->
            Map.update!(inventory, :appearances, &[Reference.new(id) | &1])

          %Stream{dictionary: %{"Type" => {:name, "EmbeddedFile"}}} ->
            Map.update!(inventory, :embedded_files, &[Reference.new(id) | &1])

          _ ->
            inventory
        end
      end
    )
    |> Map.new(fn {kind, references} -> {kind, Enum.reverse(references)} end)
  end

  defp normalize_source(%Document{} = document), do: {:ok, document}
  defp normalize_source(binary) when is_binary(binary), do: Parser.parse(binary)
  defp normalize_source(other), do: {:error, {:unsupported_pdf_source, other}}

  defp select_pages(document, selection) do
    pages = document.objects[document.pages_reference.object_id].value["Kids"]

    selected =
      case selection do
        :all -> pages
        %Range{} = range -> Enum.map(range, &Enum.at(pages, &1 - 1))
        indexes when is_list(indexes) -> Enum.map(indexes, &Enum.at(pages, &1 - 1))
      end

    if Enum.any?(selected, &is_nil/1),
      do: {:error, :page_index_out_of_range},
      else: {:ok, selected}
  end

  defp import_document(target, source, page_references) do
    reachable =
      reachable_objects(source, page_references, MapSet.new())
      |> MapSet.delete(source.pages_reference.object_id)

    {target, mapping} =
      reachable
      |> Enum.sort()
      |> Enum.reduce({target, %{}}, fn old_id, {current, mapping} ->
        {current, reference} = Document.add_object(current, nil)
        {current, Map.put(mapping, old_id, reference)}
      end)

    target =
      Enum.reduce(reachable, target, fn old_id, current ->
        old_value = source.objects[old_id].value
        new_reference = Map.fetch!(mapping, old_id)

        value =
          remap(old_value, mapping, source.pages_reference.object_id, current.pages_reference)

        Document.update_object(current, new_reference, fn _ -> value end)
      end)

    Enum.reduce(page_references, target, fn page_reference, current ->
      Document.append_page(current, Map.fetch!(mapping, page_reference.object_id))
    end)
  end

  defp reachable_objects(document, references, seen) when is_list(references),
    do: Enum.reduce(references, seen, &reachable_objects(document, &1, &2))

  defp reachable_objects(document, %Reference{object_id: id}, seen) do
    if MapSet.member?(seen, id) or not Map.has_key?(document.objects, id) do
      seen
    else
      value = document.objects[id].value
      reachable_objects(document, references_in(value), MapSet.put(seen, id))
    end
  end

  defp references_in(%Reference{} = reference), do: [reference]
  defp references_in(%Stream{dictionary: dictionary}), do: references_in(dictionary)

  defp references_in(map) when is_map(map),
    do: map |> Map.values() |> Enum.flat_map(&references_in/1)

  defp references_in(list) when is_list(list), do: Enum.flat_map(list, &references_in/1)

  defp references_in(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.flat_map(&references_in/1)

  defp references_in(_), do: []

  defp remap(%Reference{object_id: old_id}, _mapping, pages_id, target_pages)
       when old_id == pages_id, do: target_pages

  defp remap(%Reference{object_id: old_id}, mapping, _pages_id, _target_pages),
    do: Map.get(mapping, old_id, Reference.new(old_id))

  defp remap(%Stream{} = stream, mapping, pages_id, target_pages),
    do: %{stream | dictionary: remap(stream.dictionary, mapping, pages_id, target_pages)}

  defp remap(map, mapping, pages_id, target_pages) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, remap(value, mapping, pages_id, target_pages)} end)

  defp remap(list, mapping, pages_id, target_pages) when is_list(list),
    do: Enum.map(list, &remap(&1, mapping, pages_id, target_pages))

  defp remap(tuple, mapping, pages_id, target_pages) when is_tuple(tuple),
    do:
      tuple
      |> Tuple.to_list()
      |> Enum.map(&remap(&1, mapping, pages_id, target_pages))
      |> List.to_tuple()

  defp remap(value, _mapping, _pages_id, _target_pages), do: value

  defp deduplicate_resources(document) do
    candidates =
      Enum.filter(document.objects, fn {_id, object} ->
        match?(%Stream{dictionary: %{"Type" => {:name, "XObject"}}}, object.value) or
          match?(%{"Type" => {:name, "Font"}}, object.value)
      end)

    {_hashes, replacements} =
      Enum.reduce(candidates, {%{}, %{}}, fn {id, %Object{value: value}},
                                             {hashes, replacements} ->
        hash = :crypto.hash(:sha256, :erlang.term_to_binary(value))

        case Map.fetch(hashes, hash) do
          {:ok, existing} -> {hashes, Map.put(replacements, id, Reference.new(existing))}
          :error -> {Map.put(hashes, hash, id), replacements}
        end
      end)

    if map_size(replacements) == 0 do
      document
    else
      objects =
        document.objects
        |> Map.drop(Map.keys(replacements))
        |> Map.new(fn {id, object} ->
          {id, %{object | value: replace_references(object.value, replacements)}}
        end)

      %{document | objects: objects}
    end
  end

  defp replace_references(%Reference{object_id: id} = reference, replacements),
    do: Map.get(replacements, id, reference)

  defp replace_references(%Stream{} = stream, replacements),
    do: %{stream | dictionary: replace_references(stream.dictionary, replacements)}

  defp replace_references(map, replacements) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, replace_references(value, replacements)} end)

  defp replace_references(list, replacements) when is_list(list),
    do: Enum.map(list, &replace_references(&1, replacements))

  defp replace_references(tuple, replacements) when is_tuple(tuple),
    do:
      tuple
      |> Tuple.to_list()
      |> Enum.map(&replace_references(&1, replacements))
      |> List.to_tuple()

  defp replace_references(value, _replacements), do: value
end
