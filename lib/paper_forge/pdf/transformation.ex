defmodule PaperForge.PDF.Transformation do
  @moduledoc false
  alias PaperForge.{Document, Metadata, Reference, Serializer, Stream, StringEncoding}
  alias PaperForge.PDF.Graph

  def delete_pages(document, selection) do
    pages = pages(document)
    indexes = indexes(selection, length(pages)) |> MapSet.new()

    retained =
      pages
      |> Enum.with_index(1)
      |> Enum.reject(fn {_, index} -> MapSet.member?(indexes, index) end)
      |> Enum.map(&elem(&1, 0))

    document |> Graph.flatten(retained) |> modified()
  end

  def reorder_pages(document, selection) do
    pages = pages(document)
    indexes = indexes(selection, length(pages))

    unless Enum.sort(indexes) == Enum.to_list(1..length(pages)//1),
      do: raise(ArgumentError, "page order must contain every page exactly once")

    document |> Graph.flatten(Enum.map(indexes, &Enum.at(pages, &1 - 1))) |> modified()
  end

  def rotate_pages(document, selection, angle) do
    unless is_integer(angle) and rem(angle, 90) == 0,
      do: raise(ArgumentError, "rotation must be a multiple of 90 degrees")

    pages = pages(document)
    indexes = indexes(selection, length(pages)) |> MapSet.new()

    pages =
      pages
      |> Enum.with_index(1)
      |> Enum.map(fn {page, index} ->
        if MapSet.member?(indexes, index) do
          rotation = Graph.resolve!(document, Map.get(page.dictionary, "Rotate", 0))
          unless is_integer(rotation), do: raise(ArgumentError, "invalid page rotation")

          %{
            page
            | dictionary: Map.put(page.dictionary, "Rotate", Integer.mod(rotation + angle, 360))
          }
        else
          page
        end
      end)

    document |> Graph.flatten(pages) |> modified()
  end

  def update_metadata(document, options) do
    encoded = options |> Metadata.new() |> Metadata.to_dictionary()

    mapping = %{
      title: "Title",
      author: "Author",
      subject: "Subject",
      keywords: "Keywords",
      creator: "Creator",
      producer: "Producer",
      creation_date: "CreationDate",
      modification_date: "ModDate"
    }

    keys = Enum.map(options, fn {key, _} -> Map.fetch!(mapping, key) end)
    existing = Graph.resolve!(document, document.info_reference) || %{}
    value = Map.merge(Map.drop(existing, keys), Map.take(encoded, keys))

    document =
      if document.info_reference do
        Document.update_object(document, document.info_reference, fn _ -> value end)
      else
        {document, reference} = Document.add_object(document, value)
        %{document | info_reference: reference}
      end

    modified(document)
  end

  def normalize(document) do
    document = Graph.flatten(document, pages(document))
    reachable = Graph.reachable(document, [document.root_reference, document.info_reference])

    objects =
      Map.filter(document.objects, fn {id, object} ->
        MapSet.member?(reachable, Reference.new(id, object.generation))
      end)

    modified(%{document | objects: objects})
  end

  def add_watermark(document, text, options) do
    unless is_binary(text) and text != "",
      do: raise(ArgumentError, "watermark text cannot be empty")

    text = StringEncoding.literal(text)
    size = Keyword.get(options, :size, 36)
    opacity = Keyword.get(options, :opacity, 0.2)

    unless is_number(size) and size > 0 and is_number(opacity) and opacity >= 0 and opacity <= 1,
      do: raise(ArgumentError, "invalid watermark size or opacity")

    pages = pages(document)

    {document, font} =
      Document.add_object(document, %{
        "Type" => {:name, "Font"},
        "Subtype" => {:name, "Type1"},
        "BaseFont" => {:name, "Helvetica-Bold"},
        "Encoding" => {:name, "WinAnsiEncoding"}
      })

    {document, state} =
      Document.add_object(document, %{
        "Type" => {:name, "ExtGState"},
        "ca" => opacity,
        "CA" => opacity
      })

    document = Graph.flatten(document, pages)

    Enum.reduce(pages, document, fn page, document ->
      resources = Graph.resolve!(document, page.dictionary["Resources"]) || %{}
      fonts = Graph.resolve!(document, resources["Font"]) || %{}
      states = Graph.resolve!(document, resources["ExtGState"]) || %{}
      font_name = unique_name(fonts, "PFWatermark")
      state_name = unique_name(states, "PFWatermarkGS")
      box = Graph.resolve!(document, page.dictionary["CropBox"] || page.dictionary["MediaBox"])

      unless is_list(box) and length(box) == 4 and Enum.all?(box, &is_number/1),
        do: raise(ArgumentError, "invalid page box")

      [x0, y0, x1, y1] = box
      x = (x0 + x1) / 2 - byte_size(text) * size * 0.25
      y = (y0 + y1) / 2

      command =
        IO.iodata_to_binary([
          "Q\n/Artifact BMC\nq\n/",
          state_name,
          " gs\n0.5 g\nBT\n/",
          font_name,
          " ",
          Serializer.encode(size),
          " Tf\n1 0 0 1 ",
          Serializer.encode(x),
          " ",
          Serializer.encode(y),
          " Tm\n",
          Serializer.encode(text),
          " Tj\nET\nQ\nEMC\n"
        ])

      {document, before} = Document.add_object(document, Stream.new("q\n"))

      {document, after_ref} =
        Document.add_object(
          document,
          Stream.new(command, filters: if(document.compress, do: [:flate], else: []))
        )

      contents =
        case Graph.resolve!(document, page.dictionary["Contents"]) do
          nil -> []
          %Stream{} -> [page.dictionary["Contents"]]
          list when is_list(list) -> list
          _ -> raise ArgumentError, "invalid page contents"
        end

      Document.update_object(document, page.reference, fn value ->
        value
        |> Map.put(
          "Resources",
          resources
          |> Map.put("Font", Map.put(fonts, font_name, font))
          |> Map.put("ExtGState", Map.put(states, state_name, state))
        )
        |> Map.put("Contents", [before | contents] ++ [after_ref])
      end)
    end)
    |> modified()
  end

  defp unique_name(map, name),
    do: if(Map.has_key?(map, name), do: unique_name(map, name <> "_"), else: name)

  defp pages(document) do
    case Graph.pages(document) do
      {:ok, pages} -> pages
      {:error, reason} -> raise ArgumentError, "invalid page tree: #{inspect(reason)}"
    end
  end

  defp indexes(:all, count), do: Enum.to_list(1..count//1)
  defp indexes(%Range{} = range, count), do: indexes(Enum.to_list(range), count)

  defp indexes(selection, count) when is_list(selection) do
    unless Enum.all?(selection, &(is_integer(&1) and &1 > 0 and &1 <= count)),
      do: raise(ArgumentError, "page index out of range")

    unless length(Enum.uniq(selection)) == length(selection),
      do: raise(ArgumentError, "duplicate page indexes")

    selection
  end

  defp indexes(_, _), do: raise(ArgumentError, "invalid page selection")

  defp modified(document),
    do: %{document | source_info: Map.put(document.source_info, :modified, true)}
end
