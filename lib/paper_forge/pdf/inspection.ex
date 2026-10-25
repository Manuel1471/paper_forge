defmodule PaperForge.PDF.Inspection do
  @moduledoc false
  alias PaperForge.{Document, Reference, Stream}
  alias PaperForge.PDF.{Graph, Syntax}

  def page_count(document), do: length(Graph.pages!(document))

  def metadata(document),
    do: dictionary(document, document.info_reference, :invalid_info_dictionary)

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
    form = dictionary(document, catalog(document)["AcroForm"], :invalid_acroform)
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
      {[all, [field], children], seen}
    end)
    |> then(fn {values, seen} -> {List.flatten(values), seen} end)
  end

  defp fields(_, _, _, _, _, _), do: Syntax.fail(:invalid_form_fields)

  def attachments(document) do
    names = dictionary(document, catalog(document)["Names"], :invalid_names_dictionary)
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
    root = dictionary(document, catalog(document)["Outlines"], :invalid_outline)
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
    object_refs =
      Enum.flat_map(document.objects, fn {id, object} ->
        Enum.map(Graph.references(object.value), &%{object_id: id, reference: &1})
      end)

    roots =
      Enum.map(
        Graph.references([document.root_reference, document.info_reference]),
        &%{object_id: nil, reference: &1}
      )

    refs = roots ++ object_refs

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
          case inspect_feature(document, name) do
            {:ok, value} -> {Map.put(inventory, name, value), issues}
            {:error, reason} -> {Map.put(inventory, name, []), [reason | issues]}
          end
        end
      )

    cat = catalog(document)

    {mark_info, issues} =
      case safely(fn -> dictionary(document, cat["MarkInfo"], :invalid_mark_info) end) do
        {:ok, value} -> {value, issues}
        {:error, reason} -> {nil, [reason | issues]}
      end

    report =
      Map.merge(inventory, %{
        pdf_version: document.pdf_version,
        file_structure: Map.take(structure, [:file_size, :startxref, :linearized]),
        page_count: page_count,
        object_count: map_size(document.objects),
        cross_reference_type: Map.get(structure, :cross_reference_type, :generated),
        compressed_objects: Map.get(structure, :compressed_objects, 0),
        incremental_revisions: revision_count(structure),
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
          mark_info: mark_info
        },
        normalization_opportunities: opportunities(duplicates, orphaned, structure),
        issues: Enum.reverse(issues)
      })

    {:ok, report}
  catch
    {:pdf_error, reason} -> {:error, reason}
  end

  defp dictionary(document, value, error) do
    case Graph.resolve!(document, value) do
      nil -> %{}
      value when is_map(value) and not is_struct(value) -> value
      _ -> Syntax.fail(error)
    end
  end

  defp inspect_feature(document, name), do: safely(fn -> apply(__MODULE__, name, [document]) end)

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

  defp revision_count(structure) do
    max(
      length(Map.get(structure, :revisions, [])) - 1 - if(structure[:linearized], do: 1, else: 0),
      0
    )
  end

  defp opportunities(duplicates, orphaned, structure) do
    []
    |> then(&if(duplicates != [], do: &1 ++ [:deduplicate_resources], else: &1))
    |> then(&if(orphaned != [], do: &1 ++ [:remove_orphaned_objects], else: &1))
    |> then(
      &if(revision_count(structure) > 0,
        do: &1 ++ [:consolidate_revisions],
        else: &1
      )
    )
  end

  defp text(nil), do: nil

  defp text(value) when is_binary(value) or elem(value, 0) == :hex_string,
    do: PaperForge.StringEncoding.decode(value)

  defp text(_), do: Syntax.fail(:invalid_pdf_text_string)
end
