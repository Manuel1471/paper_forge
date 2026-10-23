defmodule PaperForge.PDF.Graph do
  @moduledoc """
  Generation-aware resolution and bounded traversal of an existing PDF graph.
  """
  alias PaperForge.{Document, Reference, Stream}
  alias PaperForge.PDF.Syntax
  @inherited ["Resources", "MediaBox", "CropBox", "Rotate"]

  def resolve(%Document{} = document, value) do
    {:ok, resolve!(document, value)}
  catch
    {:pdf_error, reason} -> {:error, reason}
  end

  @doc false
  def resolve!(document, value), do: resolve_value(document, value, MapSet.new())

  defp resolve_value(document, %Reference{object_id: id, generation: generation} = ref, seen) do
    if MapSet.member?(seen, ref), do: Syntax.fail({:cyclic_reference, ref})
    if MapSet.size(seen) >= 100, do: Syntax.fail({:max_depth_exceeded, 100})

    case document.objects[id] do
      %{generation: ^generation, value: value} ->
        resolve_value(document, value, MapSet.put(seen, ref))

      _ ->
        Syntax.fail({:broken_reference, id, generation})
    end
  end

  defp resolve_value(_, value, _), do: value

  def pages(document) do
    {pages, _} = walk_pages(document, document.pages_reference, %{}, MapSet.new(), 0)
    {:ok, pages}
  catch
    {:pdf_error, reason} -> {:error, reason}
  end

  @doc false
  def pages!(document) do
    case pages(document) do
      {:ok, pages} -> pages
      {:error, reason} -> Syntax.fail(reason)
    end
  end

  defp walk_pages(_, _, _, _, depth) when depth > 100, do: Syntax.fail({:max_depth_exceeded, 100})

  defp walk_pages(document, %Reference{} = reference, inherited, seen, depth) do
    if MapSet.member?(seen, reference), do: Syntax.fail(:cyclic_or_duplicate_page_tree)
    seen = MapSet.put(seen, reference)
    value = resolve!(document, reference)
    unless is_map(value) and not is_struct(value), do: Syntax.fail(:invalid_page_tree)
    inherited = Map.merge(inherited, Map.take(value, @inherited))

    case value do
      %{"Type" => {:name, "Page"}} ->
        {[%{reference: reference, dictionary: Map.merge(inherited, value)}], seen}

      %{"Type" => {:name, "Pages"}, "Kids" => kids} ->
        kids = resolve!(document, kids)
        unless is_list(kids), do: Syntax.fail(:invalid_page_tree)

        Enum.reduce(kids, {[], seen}, fn child, {pages, seen} ->
          {next, seen} = walk_pages(document, child, inherited, seen, depth + 1)
          {Enum.reverse(next, pages), seen}
        end)
        |> then(fn {pages, seen} -> {Enum.reverse(pages), seen} end)

      _ ->
        Syntax.fail(:invalid_page_tree)
    end
  end

  defp walk_pages(_, _, _, _, _), do: Syntax.fail(:invalid_page_tree)

  @doc "Returns every indirect reference in a value without following it."
  def references(%Reference{} = reference), do: [reference]
  def references(%Stream{dictionary: dictionary}), do: references(dictionary)

  def references(value) when is_map(value),
    do: value |> Map.values() |> Enum.flat_map(&references/1)

  def references(value) when is_list(value), do: Enum.flat_map(value, &references/1)
  def references(_), do: []

  @doc false
  def reachable(document, roots), do: visit(document, List.wrap(roots), MapSet.new())
  defp visit(_, [], seen), do: seen

  defp visit(document, [%Reference{object_id: id, generation: generation} = ref | tail], seen) do
    if MapSet.member?(seen, ref) do
      visit(document, tail, seen)
    else
      children =
        case document.objects[id] do
          %{generation: ^generation, value: value} -> references(value)
          _ -> []
        end

      visit(document, children ++ tail, MapSet.put(seen, ref))
    end
  end

  defp visit(document, [_ | tail], seen), do: visit(document, tail, seen)

  @doc false
  def flatten(document, pages) do
    document =
      Enum.reduce(pages, document, fn page, document ->
        Document.update_object(document, page.reference, fn _ ->
          Map.put(page.dictionary, "Parent", document.pages_reference)
        end)
      end)

    Document.update_object(document, document.pages_reference, fn value ->
      value |> Map.put("Kids", Enum.map(pages, & &1.reference)) |> Map.put("Count", length(pages))
    end)
  end
end
