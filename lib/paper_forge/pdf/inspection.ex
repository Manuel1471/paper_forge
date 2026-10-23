defmodule PaperForge.PDF.Inspection do
  @moduledoc false
  alias PaperForge.{Document, Reference, Stream}
  alias PaperForge.PDF.{Graph, Syntax}

  def page_count(document), do: length(Graph.pages!(document))

  def metadata(document),
    do: document |> Graph.resolve!(document.info_reference) |> then(&(&1 || %{}))

  defp catalog(document), do: Graph.resolve!(document, document.root_reference)

  def annotations(document) do
    Graph.pages!(document)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {page, number} ->
      values = Graph.resolve!(document, page.dictionary["Annots"]) || []
      unless is_list(values), do: Syntax.fail(:invalid_annotations)

      Enum.map(values, fn ref ->
        %{page: number, reference: ref, dictionary: Graph.resolve!(document, ref)}
      end)
    end)
  end

  def forms(document) do
    form = Graph.resolve!(document, catalog(document)["AcroForm"]) || %{}
    fields = Graph.resolve!(document, form["Fields"]) || []
    {values, _} = fields(document, fields, "", %{}, MapSet.new(), 0)
    values
  end

  defp fields(_, _, _, _, _, depth) when depth > 100, do: Syntax.fail(:form_tree_too_deep)

  defp fields(document, fields, prefix, inherited, seen, depth) when is_list(fields) do
    Enum.reduce(fields, {[], seen}, fn ref, {all, seen} ->
      if MapSet.member?(seen, ref), do: Syntax.fail(:cyclic_field_tree)
      value = Graph.resolve!(document, ref)
      unless is_map(value), do: Syntax.fail(:invalid_form_field)
      inherited = Map.merge(inherited, Map.take(value, ["FT", "Ff", "V", "DV", "DA", "Q"]))
      name = text(value["T"])
      name = Enum.reject([prefix, name], &(&1 in [nil, ""])) |> Enum.join(".")
      field = %{name: name, reference: ref, dictionary: Map.merge(inherited, value)}
      kids = Graph.resolve!(document, value["Kids"]) || []
      {children, seen} = fields(document, kids, name, inherited, MapSet.put(seen, ref), depth + 1)
      {[all, [field], children] |> List.flatten(), seen}
    end)
  end

  defp fields(_, _, _, _, _, _), do: Syntax.fail(:invalid_form_fields)

  def attachments(document) do
    names = Graph.resolve!(document, catalog(document)["Names"]) || %{}
    tree = names["EmbeddedFiles"]
    {values, _} = name_tree(document, tree, MapSet.new(), 0)

    Enum.map(values, fn {name, reference} ->
      value = Graph.resolve!(document, reference)
      %{name: text(name), reference: reference, dictionary: value}
    end)
  end

  defp name_tree(_, nil, seen, _), do: {[], seen}
  defp name_tree(_, _, _, depth) when depth > 100, do: Syntax.fail(:name_tree_too_deep)

  defp name_tree(document, ref, seen, depth) do
    if MapSet.member?(seen, ref), do: Syntax.fail(:cyclic_name_tree)
    value = Graph.resolve!(document, ref)
    unless is_map(value), do: Syntax.fail(:invalid_name_tree)
    seen = MapSet.put(seen, ref)
    pairs = Graph.resolve!(document, value["Names"]) || []
    unless is_list(pairs) and rem(length(pairs), 2) == 0, do: Syntax.fail(:invalid_name_tree)
    pairs = Enum.chunk_every(pairs, 2) |> Enum.map(fn [name, value] -> {name, value} end)
    kids = Graph.resolve!(document, value["Kids"]) || []
    unless is_list(kids), do: Syntax.fail(:invalid_name_tree)

    Enum.reduce(kids, {pairs, seen}, fn child, {all, seen} ->
      {values, seen} = name_tree(document, child, seen, depth + 1)
      {all ++ values, seen}
    end)
  end

  def outlines(document) do
    root = Graph.resolve!(document, catalog(document)["Outlines"]) || %{}
    {values, _} = outline(document, root["First"], MapSet.new(), 0)
    values
  end

  defp outline(_, nil, seen, _), do: {[], seen}
  defp outline(_, _, _, depth) when depth > 100, do: Syntax.fail(:outline_tree_too_deep)

  defp outline(document, ref, seen, depth) do
    if MapSet.member?(seen, ref), do: Syntax.fail(:cyclic_outline_tree)
    value = Graph.resolve!(document, ref)
    unless is_map(value), do: Syntax.fail(:invalid_outline)
    {children, seen} = outline(document, value["First"], MapSet.put(seen, ref), depth + 1)
    {siblings, seen} = outline(document, value["Next"], seen, depth)

    {[
       %{reference: ref, title: text(value["Title"]), dictionary: value, children: children}
       | siblings
     ], seen}
  end

  def signatures(document) do
    document.objects
    |> Enum.sort()
    |> Enum.flat_map(fn {id, object} ->
      case object.value do
        %{"Type" => {:name, "Sig"}} = value -> [signature(id, object.generation, value)]
        %{"ByteRange" => _, "Contents" => _} = value -> [signature(id, object.generation, value)]
        _ -> []
      end
    end)
  end

  defp signature(id, generation, value),
    do: %{
      reference: Reference.new(id, generation),
      dictionary: value,
      verification: :not_performed
    }

  def analyze(%Document{} = document) do
    try do
      refs =
        Enum.flat_map(document.objects, fn {id, object} ->
          Enum.map(Graph.references(object.value), &%{object_id: id, reference: &1})
        end)

      broken =
        Enum.filter(refs, fn %{reference: ref} ->
          case document.objects[ref.object_id] do
            %{generation: generation} -> generation != ref.generation
            _ -> true
          end
        end)

      reachable = Graph.reachable(document, [document.root_reference, document.info_reference])

      orphaned =
        document.objects
        |> Enum.sort()
        |> Enum.reject(fn {id, object} ->
          MapSet.member?(reachable, Reference.new(id, object.generation))
        end)
        |> Enum.map(fn {id, object} -> Reference.new(id, object.generation) end)

      resources = resources(document)
      duplicates = resources.fonts ++ resources.images

      duplicates =
        duplicates
        |> Enum.group_by(fn ref ->
          :crypto.hash(
            :sha256,
            :erlang.term_to_binary(Graph.resolve!(document, ref), [:deterministic])
          )
        end)
        |> Map.values()
        |> Enum.filter(&(length(&1) > 1))
        |> Enum.sort()

      {page_count, page_issues} =
        case Graph.pages(document) do
          {:ok, pages} -> {length(pages), []}
          {:error, reason} -> {nil, [reason]}
        end

      structure = document.source_info

      {inventory, issues} =
        Enum.reduce(
          [:forms, :annotations, :attachments, :outlines, :signatures],
          {%{}, page_issues},
          fn name, {inventory, issues} ->
            case safely(fn -> apply(__MODULE__, name, [document]) end) do
              {:ok, value} -> {Map.put(inventory, name, value), issues}
              {:error, reason} -> {Map.put(inventory, name, []), [reason | issues]}
            end
          end
        )

      cat = catalog(document)

      report =
        Map.merge(inventory, %{
          pdf_version: document.pdf_version,
          file_structure: Map.take(structure, [:file_size, :startxref]),
          page_count: page_count,
          object_count: map_size(document.objects),
          cross_reference_type: Map.get(structure, :cross_reference_type, :generated),
          compressed_objects: Map.get(structure, :compressed_objects, 0),
          incremental_revisions: max(length(Map.get(structure, :revisions, [])) - 1, 0),
          revisions: Map.get(structure, :revisions, []),
          fonts: resources.fonts,
          images: resources.images,
          duplicate_resources: duplicates,
          broken_references: broken,
          orphaned_objects: orphaned,
          encryption: structure[:encryption],
          permissions: get_in(structure, [:encryption, :permissions]),
          tagged_pdf: %{
            structure_tree: cat["StructTreeRoot"],
            mark_info: Graph.resolve!(document, cat["MarkInfo"])
          },
          normalization_opportunities: opportunities(duplicates, orphaned, structure),
          issues: Enum.reverse(issues)
        })

      {:ok, report}
    catch
      {:pdf_error, reason} -> {:error, reason}
    end
  end

  defp safely(fun) do
    {:ok, fun.()}
  catch
    {:pdf_error, reason} -> {:error, reason}
  end

  defp resources(document) do
    Enum.reduce(Enum.sort(document.objects), %{fonts: [], images: []}, fn {id, object}, acc ->
      ref = Reference.new(id, object.generation)

      case object.value do
        %{"Type" => {:name, "Font"}} ->
          Map.update!(acc, :fonts, &(&1 ++ [ref]))

        %Stream{dictionary: %{"Subtype" => {:name, "Image"}}} ->
          Map.update!(acc, :images, &(&1 ++ [ref]))

        _ ->
          acc
      end
    end)
  end

  defp opportunities(duplicates, orphaned, structure) do
    []
    |> then(&if(duplicates != [], do: &1 ++ [:deduplicate_resources], else: &1))
    |> then(&if(orphaned != [], do: &1 ++ [:remove_orphaned_objects], else: &1))
    |> then(
      &if(length(Map.get(structure, :revisions, [])) > 1,
        do: &1 ++ [:consolidate_revisions],
        else: &1
      )
    )
  end

  defp text({:hex_string, bytes}), do: text(bytes)

  defp text(<<254, 255, bytes::binary>>),
    do: :unicode.characters_to_binary(bytes, {:utf16, :big}, :utf8)

  defp text(value), do: value
end
