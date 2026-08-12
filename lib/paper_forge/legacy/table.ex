defmodule PaperForge.Legacy.Table do
  @moduledoc false

  alias PaperForge.Document
  alias PaperForge.Page

  @spec add(Document.t(), [[term()]], keyword(), keyword()) :: Document.t()
  def add(%Document{} = document, rows, page_options, options)
      when is_list(rows) and is_list(page_options) and is_list(options) do
    validate_row_split!(Keyword.get(options, :row_split, :keep))
    page_options = Keyword.put_new(page_options, :origin, :top_left)
    page = Page.new(page_options)
    row_height = Keyword.get(options, :row_height, 24)
    y = Keyword.get(options, :y, Page.content_top(page))
    rows_per_page = max(floor((Page.content_bottom(page) - y) / row_height), 1)

    header_rows =
      if Keyword.get(options, :repeat_header, false),
        do: Keyword.get(options, :header_rows, 1),
        else: 0

    {headers, body_rows} = Enum.split(rows, header_rows)
    body_capacity = max(rows_per_page - header_rows, 1)

    Enum.reduce(Enum.chunk_every(body_rows, body_capacity), document, fn chunk,
                                                                         current_document ->
      page =
        Page.new(page_options)
        |> Page.table(
          headers ++ chunk,
          table_page_options(Page.new(page_options), options, header_rows > 0)
        )

      Page.add_to_document(page, current_document)
    end)
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
