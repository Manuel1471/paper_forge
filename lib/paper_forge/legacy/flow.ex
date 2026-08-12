defmodule PaperForge.Legacy.Flow do
  @moduledoc false

  alias PaperForge.Document
  alias PaperForge.Page
  alias PaperForge.TextWrapper

  @spec layout(Document.t(), [iodata()], keyword(), keyword()) :: {Document.t(), map()}
  def layout(%Document{} = document, blocks, page_options, options)
      when is_list(blocks) and is_list(page_options) and is_list(options) do
    page_options = Keyword.put_new(page_options, :origin, :top_left)
    page = page_options |> Page.new() |> decorate_page(options)
    font_key = Document.resolve_font_key(document, options)
    {document, font} = Document.register_font(document, font_key)

    state = %{
      document: document,
      page: page,
      page_options: page_options,
      cursor_y: Keyword.get(options, :y, Page.content_top(page)),
      bottom_y: Page.content_bottom(page),
      x: Keyword.get(options, :x, Page.content_left(page)),
      width: Keyword.get(options, :width, Page.content_width(page)),
      font_key: font_key,
      font: font,
      size: Keyword.get(options, :size, 12),
      line_height: Keyword.get(options, :line_height, Keyword.get(options, :size, 12) * 1.2),
      gap: Keyword.get(options, :gap, Keyword.get(options, :size, 12) * 0.5),
      options: options,
      has_content?: false,
      pages_added: 0,
      blocks_seen: 0,
      overflow?: false
    }

    state =
      blocks
      |> Enum.reduce(state, fn block, current_state ->
        flow_block(IO.iodata_to_binary(block), current_state)
      end)
      |> finish()

    {state.document,
     %{
       pages_added: state.pages_added,
       blocks: state.blocks_seen,
       overflow?: state.overflow? or state.pages_added > 1
     }}
  end

  defp flow_block("", state), do: state

  defp flow_block(block, state) do
    lines =
      TextWrapper.wrap(block,
        width: state.width,
        font: state.font_key,
        font_instance: state.font,
        size: state.size
      )

    state = %{state | blocks_seen: state.blocks_seen + 1}

    if Keyword.get(state.options, :keep_together, false) and state.has_content? and
         length(lines) * state.line_height > state.bottom_y - state.cursor_y do
      state |> next_page() |> then(&flow_lines(lines, &1))
    else
      flow_lines(lines, state)
    end
  end

  defp flow_lines([], state), do: state

  defp flow_lines(lines, state) do
    state = if state.cursor_y >= state.bottom_y, do: next_page(state), else: state
    max_lines = max(floor((state.bottom_y - state.cursor_y) / state.line_height), 1)
    {visible_lines, remaining_lines} = Enum.split(lines, max_lines)
    consumed_height = length(visible_lines) * state.line_height

    page =
      Page.text_box(
        state.page,
        Enum.join(visible_lines, "\n"),
        state.options
        |> Keyword.put(:x, state.x)
        |> Keyword.put(:y, state.cursor_y)
        |> Keyword.put(:width, state.width)
        |> Keyword.put(:height, consumed_height)
        |> Keyword.put(:font, state.font_key)
        |> Keyword.put(:size, state.size)
        |> Keyword.put(:line_height, state.line_height)
      )

    state = %{
      state
      | page: page,
        cursor_y: state.cursor_y + consumed_height + state.gap,
        has_content?: true,
        overflow?: state.overflow? or remaining_lines != []
    }

    if remaining_lines == [],
      do: state,
      else: state |> next_page() |> then(&flow_lines(remaining_lines, &1))
  end

  defp next_page(%{has_content?: false} = state), do: state

  defp next_page(state) do
    document = Page.add_to_document(state.page, state.document)
    page = state.page_options |> Page.new() |> decorate_page(state.options)

    %{
      state
      | document: document,
        page: page,
        cursor_y: Page.content_top(page),
        bottom_y: Page.content_bottom(page),
        has_content?: false,
        pages_added: state.pages_added + 1
    }
  end

  defp finish(%{has_content?: true} = state) do
    %{
      state
      | document: Page.add_to_document(state.page, state.document),
        pages_added: state.pages_added + 1
    }
  end

  defp finish(state), do: state

  defp decorate_page(page, options),
    do: page |> maybe_add_header(options) |> maybe_add_footer(options)

  defp maybe_add_header(page, options) do
    case Keyword.get(options, :header) do
      nil ->
        page

      text when is_binary(text) ->
        Page.text(page, text,
          x: Page.content_left(page),
          y: Keyword.get(options, :header_y, max(Page.content_top(page) - 28, 12)),
          width: Page.content_width(page),
          align: Keyword.get(options, :header_align, :center),
          font: Keyword.get(options, :header_font, Keyword.get(options, :font, :helvetica)),
          size: Keyword.get(options, :header_size, 9)
        )

      fun when is_function(fun, 1) ->
        fun.(page)
    end
  end

  defp maybe_add_footer(page, options) do
    case Keyword.get(options, :footer) do
      nil ->
        page

      text when is_binary(text) ->
        Page.text(page, text,
          x: Page.content_left(page),
          y:
            Keyword.get(options, :footer_y, min(Page.content_bottom(page) + 22, page.height - 12)),
          width: Page.content_width(page),
          align: Keyword.get(options, :footer_align, :center),
          font: Keyword.get(options, :footer_font, Keyword.get(options, :font, :helvetica)),
          size: Keyword.get(options, :footer_size, 9)
        )

      fun when is_function(fun, 1) ->
        fun.(page)
    end
  end
end
