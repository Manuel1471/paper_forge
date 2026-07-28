defmodule PaperForge.Layout.Engine do
  @moduledoc false

  alias PaperForge.Document
  alias PaperForge.Flow
  alias PaperForge.Layout.Block
  alias PaperForge.LayoutError
  alias PaperForge.NavigationError
  alias PaperForge.Page
  alias PaperForge.PageContext
  alias PaperForge.PageTemplateError
  alias PaperForge.TableError
  alias PaperForge.TextWrapper

  @default_page_options [size: :a4, origin: :top_left, margins: 72]

  @spec render(Document.t(), Flow.t(), keyword()) :: {Document.t(), map()}
  def render(%Document{} = document, %Flow{} = flow, options \\ []) do
    page_options =
      options
      |> Keyword.get(:page_options, @default_page_options)
      |> Keyword.put_new(:origin, :top_left)

    blocks =
      flow.blocks
      |> Enum.reverse()
      |> expand_blocks(nil, options, document)

    validate_navigation!(blocks)

    pages =
      paginate(blocks, page_options, document, options)

    total_pages =
      length(pages)

    {document, rendered_pages} =
      pages
      |> Enum.with_index(1)
      |> Enum.reduce({document, []}, fn {page_spec, page_number}, {current_document, rendered} ->
        placements = page_spec.placements
        page_options = page_spec.options
        render_options = page_spec.render_options

        context =
          page_context(page_options, page_number, total_pages, placements)

        page =
          page_options
          |> Page.new()
          |> render_template(:header, render_options, context)
          |> render_placements(placements, context, current_document)
          |> render_template(:footer, render_options, context)

        {
          PaperForge.add_page(current_document, page),
          [page | rendered]
        }
      end)

    report =
      %{
        pages: total_pages,
        blocks: length(blocks),
        placements: Enum.flat_map(pages, & &1.placements),
        warnings: [],
        rendered_pages: Enum.reverse(rendered_pages)
      }

    {document, report}
  end

  defp expand_blocks(blocks, section, options, document) do
    Enum.flat_map(blocks, fn
      %Block{type: :section, content: section_id, children: children, options: block_options} =
          block ->
        section_options =
          options
          |> Keyword.merge(resolve_section_template_options(block_options, document))
          |> Keyword.merge(Keyword.drop(block_options, [:title, :children]))

        heading =
          case Keyword.get(block_options, :title) do
            nil ->
              []

            title ->
              [
                Block.new(:heading, title,
                  id: "#{block.id}-heading",
                  level: 1,
                  destination: section_id,
                  bookmark: true,
                  page_break_before: Keyword.get(block_options, :page_break_before, false),
                  section: section_id,
                  layout_options: section_options
                )
              ]
          end

        expanded_children =
          expand_blocks(children, section_id, section_options, document)

        page_break =
          if Keyword.get(block_options, :page_break_after, false) do
            [Block.new(:page_break, nil, layout_options: section_options)]
          else
            []
          end

        heading ++ expanded_children ++ page_break

      %Block{type: :container, children: children, options: block_options} = block ->
        [
          %{
            block
            | children:
                children
                |> expand_blocks(section, Keyword.merge(options, block_options), document),
              options:
                block.options
                |> Keyword.put_new(:section, section)
                |> Keyword.put_new(:layout_options, options)
          }
        ]

      %Block{} = block ->
        [
          %{
            block
            | options:
                block.options
                |> Keyword.put_new(:section, section)
                |> Keyword.put_new(:layout_options, options)
          }
        ]
    end)
  end

  defp resolve_section_template_options(block_options, document) do
    case Keyword.get(block_options, :template) do
      nil ->
        []

      template ->
        case Document.fetch_page_template(document, template) do
          {:ok, template_options} ->
            template_options

          :error ->
            raise PageTemplateError,
              reason: :unknown_template,
              template: template
        end
    end
  end

  defp paginate(blocks, page_options, document, options) do
    page = Page.new(page_options)

    initial = %{
      pages: [%{options: page_options, render_options: options, placements: []}],
      page_number: 1,
      cursor_y: Page.content_top(page),
      bottom_y: Page.content_bottom(page),
      page: page,
      page_options: page_options,
      render_options: options,
      document: document,
      options: options
    }

    blocks
    |> Enum.reduce(initial, &place_block/2)
    |> Map.fetch!(:pages)
    |> Enum.reject(&(&1.placements == []))
  end

  defp place_block(%Block{type: :page_break} = block, state) do
    block
    |> apply_block_layout_options(state)
    |> next_page()
  end

  defp place_block(%Block{type: :container, children: children, options: options} = block, state) do
    state = apply_block_layout_options(block, state)

    height =
      children
      |> Enum.map(&block_height(&1, state))
      |> Enum.sum()

    if Keyword.get(options, :keep_together, false) and height > available_height(state) and
         state.cursor_y > Page.content_top(state.page) do
      place_children(children, next_page(state))
    else
      if height > state.bottom_y - Page.content_top(state.page) do
        raise LayoutError,
          reason: :block_too_large,
          block_id: block.id,
          page_number: state.page_number,
          block_type: block.type,
          metadata: %{
            required_height: height,
            available_height: state.bottom_y - Page.content_top(state.page)
          }
      end

      place_children(children, state)
    end
  end

  defp place_block(%Block{type: :paragraph} = block, state) do
    state = maybe_page_break_before(block, state)
    lines = paragraph_lines(block, state)
    state = place_text_lines(block, lines, state)
    maybe_page_break_after(block, state)
  end

  defp place_block(%Block{type: :heading} = block, state) do
    state = maybe_page_break_before(block, state)

    state =
      if Keyword.get(block.options, :keep_with_next, true) and
           current_page_has_content?(state) do
        required_height =
          block_height(block, state) + Keyword.get(block.options, :min_remaining, 48)

        if required_height > available_height(state), do: next_page(state), else: state
      else
        state
      end

    state = place_text_lines(block, [block.content], state)
    maybe_page_break_after(block, state)
  end

  defp place_block(%Block{type: :list} = block, state) do
    state = maybe_page_break_before(block, state)

    item_blocks =
      block.content
      |> Enum.with_index(1)
      |> Enum.map(fn {item, index} ->
        marker =
          case Keyword.get(block.options, :type, :unordered) do
            :ordered -> "#{index}."
            :unordered -> "•"
          end

        Block.new(
          :paragraph,
          "#{marker} #{item}",
          Keyword.merge(block.options,
            id: "#{block.id}-item-#{index}",
            first_line_indent: Keyword.get(block.options, :marker_width, 24)
          )
        )
      end)

    state = place_children(item_blocks, state)
    maybe_page_break_after(block, state)
  end

  defp place_block(%Block{type: :table} = block, state) do
    state = maybe_page_break_before(block, state)
    row_height = Keyword.get(block.options, :row_height, 24)
    repeat_header = Keyword.get(block.options, :repeat_header, true)
    header_rows = if repeat_header, do: Keyword.get(block.options, :header_rows, 1), else: 0
    rows = block.content.rows
    {headers, body_rows} = Enum.split(rows, header_rows)

    rows_per_page =
      max(
        floor(available_height(state) / row_height),
        1
      )

    if row_height > state.bottom_y - Page.content_top(state.page) do
      raise TableError, reason: :row_too_large, block_id: block.id, row: 0
    end

    body_capacity = max(rows_per_page - header_rows, 1)

    body_rows
    |> Enum.chunk_every(body_capacity)
    |> Enum.with_index()
    |> Enum.reduce(state, fn {chunk, index}, current_state ->
      rows = headers ++ chunk
      height = length(rows) * row_height

      current_state =
        if height > available_height(current_state) and current_page_has_content?(current_state) do
          next_page(current_state)
        else
          current_state
        end

      fragment = %{
        id: "#{block.id}-part-#{index + 1}",
        type: :table,
        block: block,
        y: current_state.cursor_y,
        height: height,
        rows: rows
      }

      add_fragment(current_state, fragment)
    end)
    |> then(&maybe_page_break_after(block, &1))
  end

  defp place_block(%Block{type: :image} = block, state) do
    state = maybe_page_break_before(block, state)
    height = Keyword.get(block.options, :height, 120)

    ensure_fits_empty_page!(block, height, state)

    state =
      if height > available_height(state) and current_page_has_content?(state) do
        next_page(state)
      else
        state
      end

    state =
      add_fragment(state, %{
        id: block.id,
        type: :image,
        block: block,
        y: state.cursor_y,
        height: min(height, available_height(state))
      })

    maybe_page_break_after(block, state)
  end

  defp place_block(%Block{type: :separator} = block, state) do
    state = maybe_page_break_before(block, state)
    height = Keyword.get(block.options, :height, 12)

    ensure_fits_empty_page!(block, height, state)

    state =
      add_fragment(state, %{
        id: block.id,
        type: :separator,
        block: block,
        y: state.cursor_y,
        height: height
      })

    maybe_page_break_after(block, state)
  end

  defp place_block(%Block{type: :spacer} = block, state) do
    state = maybe_page_break_before(block, state)
    ensure_fits_empty_page!(block, block.content, state)

    state =
      add_fragment(state, %{
        id: block.id,
        type: :spacer,
        block: block,
        y: state.cursor_y,
        height: block.content
      })

    maybe_page_break_after(block, state)
  end

  defp place_block(%Block{type: :custom} = block, state) do
    state = maybe_page_break_before(block, state)
    height = Keyword.get(block.options, :height, 0)
    ensure_fits_empty_page!(block, height, state)

    state =
      add_fragment(state, %{
        id: block.id,
        type: :custom,
        block: block,
        y: state.cursor_y,
        height: height
      })

    maybe_page_break_after(block, state)
  end

  defp place_children(children, state) do
    Enum.reduce(children, state, &place_block/2)
  end

  defp place_text_lines(block, lines, state) do
    line_height = line_height(block)
    space_before = Keyword.get(block.options, :space_before, 0)
    space_after = Keyword.get(block.options, :space_after, default_space_after(block))
    available_lines = max(floor(max(available_height(state) - space_before, 0) / line_height), 1)
    {visible, remaining} = Enum.split(lines, available_lines)
    height = length(visible) * line_height + space_before + space_after
    ensure_fits_empty_page!(block, height, state)

    state =
      if height > available_height(state) and current_page_has_content?(state) do
        next_page(state)
      else
        state
      end

    fragment = %{
      id: block.id,
      type: block.type,
      block: block,
      y: state.cursor_y + space_before,
      height: height,
      lines: visible
    }

    state = add_fragment(state, fragment)

    if remaining == [] do
      state
    else
      place_text_lines(block, remaining, next_page(state))
    end
  end

  defp add_fragment(state, fragment) do
    pages =
      List.update_at(
        state.pages,
        -1,
        fn page ->
          %{page | placements: page.placements ++ [placement(fragment, state)]}
        end
      )

    %{
      state
      | pages: pages,
        cursor_y: state.cursor_y + fragment.height
    }
  end

  defp next_page(%{pages: pages} = state) do
    new_page = Page.new(state.page_options)

    %{
      state
      | pages:
          pages ++
            [%{options: state.page_options, render_options: state.render_options, placements: []}],
        page_number: state.page_number + 1,
        page: new_page,
        cursor_y: Page.content_top(new_page),
        bottom_y: Page.content_bottom(new_page)
    }
  end

  defp available_height(state), do: max(state.bottom_y - state.cursor_y, 0)
  defp current_page_has_content?(state), do: List.last(state.pages).placements != []

  defp placement(fragment, state) do
    fragment
    |> Map.put(:page_number, state.page_number)
    |> Map.put(:x, fragment_x(fragment, state.page))
    |> Map.put(:width, fragment_width(fragment, state.page))
    |> Map.put(:section, Keyword.get(fragment.block.options, :section))
  end

  defp fragment_x(%{block: block}, page),
    do: Keyword.get(block.options, :x, Page.content_left(page))

  defp fragment_width(%{block: block}, page) do
    case Keyword.get(block.options, :width, Page.content_width(page)) do
      :content -> Page.content_width(page)
      width -> width
    end
  end

  defp maybe_page_break_before(block, state) do
    state = apply_block_layout_options(block, state)

    if Keyword.get(block.options, :page_break_before, false) and current_page_has_content?(state) do
      next_page(state)
    else
      state
    end
  end

  defp maybe_page_break_after(block, state) do
    if Keyword.get(block.options, :page_break_after, false), do: next_page(state), else: state
  end

  defp apply_block_layout_options(%Block{} = block, state) do
    block.options
    |> Keyword.get(:layout_options, [])
    |> apply_layout_options(state)
  end

  defp apply_layout_options(options, state) do
    new_render_options =
      Keyword.merge(state.render_options, options)

    new_page_options =
      case page_options_from(options) do
        [] ->
          state.page_options

        page_options ->
          state.page_options |> Keyword.merge(page_options) |> Keyword.put_new(:origin, :top_left)
      end

    if new_page_options == state.page_options and new_render_options == state.render_options do
      state
    else
      state =
        if current_page_has_content?(state), do: next_page(state), else: state

      page = Page.new(new_page_options)

      pages =
        List.update_at(state.pages, -1, fn page_spec ->
          %{page_spec | options: new_page_options, render_options: new_render_options}
        end)

      %{
        state
        | pages: pages,
          page: page,
          page_options: new_page_options,
          render_options: new_render_options,
          cursor_y: Page.content_top(page),
          bottom_y: Page.content_bottom(page)
      }
    end
  end

  defp page_options_from(options) do
    nested_options = Keyword.get(options, :page_options, [])

    direct_options =
      Keyword.take(options, [:size, :orientation, :origin, :margins])

    Keyword.merge(direct_options, nested_options)
  end

  defp ensure_fits_empty_page!(block, height, state) do
    full_height = state.bottom_y - Page.content_top(state.page)

    if height > full_height do
      raise LayoutError,
        reason: :block_too_large,
        block_id: block.id,
        page_number: state.page_number,
        block_type: block.type,
        metadata: %{
          required_height: height,
          available_height: full_height
        }
    end
  end

  defp block_height(%Block{type: :paragraph} = block, state),
    do: length(paragraph_lines(block, state)) * line_height(block)

  defp block_height(%Block{type: :heading} = block, _state), do: line_height(block)
  defp block_height(%Block{type: :spacer, content: height}, _state), do: height

  defp block_height(%Block{type: :separator} = block, _state),
    do: Keyword.get(block.options, :height, 12)

  defp block_height(%Block{type: :image} = block, _state),
    do: Keyword.get(block.options, :height, 120)

  defp block_height(%Block{type: :custom} = block, _state),
    do: Keyword.get(block.options, :height, 0)

  defp block_height(%Block{type: :table} = block, _state) do
    Keyword.get(block.options, :row_height, 24) * length(block.content.rows)
  end

  defp block_height(%Block{type: :list} = block, state) do
    block.content
    |> Enum.map(fn item ->
      item_block = Block.new(:paragraph, to_string(item), block.options)
      block_height(item_block, state)
    end)
    |> Enum.sum()
  end

  defp paragraph_lines(block, state) do
    TextWrapper.wrap(
      block.content,
      width: Keyword.get(block.options, :width, Page.content_width(state.page)),
      font: Keyword.get(block.options, :font, :helvetica),
      size: Keyword.get(block.options, :size, default_size(block))
    )
  end

  defp line_height(block),
    do: Keyword.get(block.options, :line_height, default_size(block) * 1.35)

  defp default_size(%Block{type: :heading, options: options}),
    do: 24 - (Keyword.get(options, :level, 1) - 1) * 2

  defp default_size(_block), do: 11
  defp default_space_after(%Block{type: :heading}), do: 10
  defp default_space_after(_block), do: 4

  defp page_context(page_options, page_number, total_pages, placements) do
    page = Page.new(page_options)
    heading = current_heading(placements)

    %PageContext{
      page_number: page_number,
      total_pages: total_pages,
      page_width: page.width,
      page_height: page.height,
      content_left: Page.content_left(page),
      content_top: Page.content_top(page),
      content_right: Page.content_left(page) + Page.content_width(page),
      content_bottom: Page.content_bottom(page),
      content_width: Page.content_width(page),
      content_height: Page.content_height(page),
      section: current_section(placements),
      current_heading: heading
    }
  end

  defp current_heading(placements) do
    placements
    |> Enum.find_value(fn
      %{type: :heading, lines: [heading | _rest]} -> heading
      _placement -> nil
    end)
  end

  defp current_section(placements) do
    placements
    |> Enum.find_value(fn placement ->
      Keyword.get(placement.block.options, :section)
    end)
  end

  defp render_template(page, key, options, context) do
    case Keyword.get(options, key) do
      nil -> page
      fun when is_function(fun, 2) -> fun.(page, context)
      text when is_binary(text) -> render_template_text(page, key, text, context)
    end
  end

  defp validate_navigation!(blocks) do
    destinations =
      blocks
      |> Enum.flat_map(&destination_names/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&normalize_destination/1)

    duplicate =
      destinations
      |> Enum.frequencies()
      |> Enum.find_value(fn
        {destination, count} when count > 1 -> destination
        _entry -> nil
      end)

    if duplicate do
      raise NavigationError,
        reason: :duplicate_destination,
        destination: duplicate
    end

    links =
      blocks
      |> Enum.flat_map(&link_targets/1)
      |> Enum.map(&normalize_destination/1)

    case Enum.find(links, &(&1 not in destinations)) do
      nil ->
        :ok

      missing ->
        raise NavigationError,
          reason: :unresolved_destination,
          destination: missing
    end
  end

  defp destination_names(%Block{type: :container, children: children}) do
    Enum.flat_map(children, &destination_names/1)
  end

  defp destination_names(%Block{type: :heading} = block) do
    case Keyword.get(block.options, :destination, true) do
      false -> []
      true -> [block.id]
      destination -> [destination]
    end
  end

  defp destination_names(_block), do: []

  defp link_targets(%Block{type: :container, children: children}) do
    Enum.flat_map(children, &link_targets/1)
  end

  defp link_targets(%Block{} = block) do
    block.options
    |> Keyword.get(:link_to)
    |> List.wrap()
  end

  defp normalize_destination(destination) when is_atom(destination),
    do: Atom.to_string(destination)

  defp normalize_destination(destination), do: destination

  defp render_template_text(page, :header, text, context) do
    Page.text(page, text,
      x: context.content_left,
      y: max(context.content_top - 28, 12),
      width: context.content_width,
      align: :center,
      size: 9
    )
  end

  defp render_template_text(page, :footer, text, context) do
    text =
      text
      |> String.replace("{page}", Integer.to_string(context.page_number))
      |> String.replace("{total}", Integer.to_string(context.total_pages))

    Page.text(page, text,
      x: context.content_left,
      y: min(context.content_bottom + 24, context.page_height - 12),
      width: context.content_width,
      align: :center,
      size: 9
    )
  end

  defp render_placements(page, placements, context, document) do
    Enum.reduce(placements, page, fn placement, current_page ->
      render_placement(current_page, placement, context, document)
    end)
  end

  defp render_placement(page, %{type: type, block: block, y: y} = placement, _context, _document)
       when type in [:paragraph, :heading] do
    text = Enum.join(placement.lines, "\n")
    level = Keyword.get(block.options, :level, 1)
    size = Keyword.get(block.options, :size, default_size(block))

    page =
      if type == :heading and Keyword.get(block.options, :destination, true) != false do
        destination = Keyword.get(block.options, :destination, block.id)

        page
        |> Page.destination(destination, y: y)
        |> maybe_bookmark(block, text, y)
      else
        page
      end

    Page.text_box(page, text,
      x: Keyword.get(block.options, :x, Page.content_left(page)),
      y: y,
      width: Keyword.get(block.options, :width, Page.content_width(page)),
      font: Keyword.get(block.options, :font, :helvetica),
      size: size,
      line_height: line_height(block),
      align: Keyword.get(block.options, :align, :left),
      color: Keyword.get(block.options, :color, PaperForge.Color.black()),
      weight: if(level <= 2, do: :bold, else: :regular)
    )
  end

  defp render_placement(
         page,
         %{type: :table, block: block, y: y, rows: rows},
         _context,
         _document
       ) do
    Page.table(page, rows,
      x: Keyword.get(block.options, :x, Page.content_left(page)),
      y: y,
      width: Keyword.get(block.options, :width, Page.content_width(page)),
      row_height: Keyword.get(block.options, :row_height, 24),
      padding: Keyword.get(block.options, :padding, 6),
      header: Keyword.get(block.options, :repeat_header, true),
      font: Keyword.get(block.options, :font, :helvetica),
      size: Keyword.get(block.options, :size, 9)
    )
  end

  defp render_placement(
         page,
         %{type: :image, block: block, y: y, height: height},
         _context,
         _document
       ) do
    width =
      case Keyword.get(block.options, :width, :content) do
        :content -> Page.content_width(page)
        value -> value
      end

    x =
      case Keyword.get(block.options, :align, :left) do
        :center -> Page.content_left(page) + (Page.content_width(page) - width) / 2
        :right -> Page.content_left(page) + Page.content_width(page) - width
        _left -> Page.content_left(page)
      end

    page
    |> Page.image(block.content, x: x, y: y, width: width, height: height)
    |> maybe_render_caption(block, y + height + 4, width, x)
  end

  defp render_placement(page, %{type: :separator, block: block, y: y}, _context, _document) do
    Page.line(page,
      x1: Page.content_left(page),
      y1: y + Keyword.get(block.options, :height, 12) / 2,
      x2: Page.content_left(page) + Page.content_width(page),
      y2: y + Keyword.get(block.options, :height, 12) / 2,
      width: Keyword.get(block.options, :line_width, 1)
    )
  end

  defp render_placement(page, %{type: :spacer}, _context, _document), do: page

  defp render_placement(page, %{type: :custom, block: block}, context, _document) do
    block.content.(page, context)
  end

  defp maybe_bookmark(page, block, title, y) do
    if Keyword.get(block.options, :bookmark, true) do
      Page.bookmark(page, title, y: y)
    else
      page
    end
  end

  defp maybe_render_caption(page, block, y, width, x) do
    case Keyword.get(block.options, :caption) do
      nil ->
        page

      caption ->
        Page.text(page, caption,
          x: x,
          y: y,
          width: width,
          align: :center,
          size: Keyword.get(block.options, :caption_size, 9)
        )
    end
  end
end
