defmodule PaperForge.Legacy.Table do
  @moduledoc false

  alias PaperForge.Document
  alias PaperForge.Layout.Geometry
  alias PaperForge.Page

  @spec add(Document.t(), [[term()]], keyword(), keyword()) :: Document.t()
  def add(%Document{} = document, rows, page_options, options)
      when is_list(rows) and is_list(page_options) and is_list(options) do
    validate_row_split!(Keyword.get(options, :row_split, :keep))
    page_options = Keyword.put_new(page_options, :origin, :top_left)
    page = Geometry.page!(page_options)
    {headers, chunks} = paginate_rows(rows, page, options)

    Enum.reduce(chunks, document, fn chunk, current_document ->
      page =
        Geometry.page!(page_options)
        |> Page.table(
          headers ++ chunk,
          table_page_options(page, options, headers != [])
        )

      Page.add_to_document(page, current_document)
    end)
  end

  defp paginate_rows(rows, page, options) do
    rows_per_page = row_capacity(page, options)

    header_rows =
      if Keyword.get(options, :repeat_header, false),
        do: Keyword.get(options, :header_rows, 1),
        else: 0

    unless is_integer(header_rows) and header_rows >= 0 do
      raise ArgumentError, "header_rows must be a non-negative integer"
    end

    {headers, body_rows} = Enum.split(rows, header_rows)
    required_rows = length(headers) + if(body_rows == [], do: 0, else: 1)

    if required_rows > rows_per_page do
      raise ArgumentError, "table headers and at least one body row must fit within the page"
    end

    body_capacity = max(rows_per_page - length(headers), 1)

    chunks =
      if body_rows == [] and headers != [],
        do: [[]],
        else: Enum.chunk_every(body_rows, body_capacity)

    {headers, chunks}
  end

  defp row_capacity(page, options) do
    row_height = Keyword.get(options, :row_height, 24)
    y = Keyword.get(options, :y, Page.content_top(page))

    unless is_number(row_height) and row_height > 0 do
      raise ArgumentError, "row_height must be positive"
    end

    floor((Page.content_bottom(page) - y) / row_height)
  end

  defp validate_row_split!(:keep), do: :ok

  defp validate_row_split!(value),
    do: raise(ArgumentError, "unsupported row split policy #{inspect(value)}. Expected :keep")

  defp table_page_options(page, options, header?) do
    options
    |> Keyword.put_new(:x, Page.content_left(page))
    |> Keyword.put_new(:y, Page.content_top(page))
    |> Keyword.put_new(:width, Page.content_width(page))
    |> Keyword.put(:header, header?)
    |> Keyword.delete(:repeat_header)
    |> Keyword.delete(:header_rows)
    |> Keyword.delete(:row_split)
  end
end
