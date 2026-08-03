defmodule PaperForge.Layout.Engine do
  @moduledoc false

  alias PaperForge.Document
  alias PaperForge.Flow
  alias PaperForge.FontRegistry
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

    source_blocks =
      flow.blocks
      |> Enum.reverse()
      |> expand_blocks(nil, options, document)
      |> materialize_notes()
      |> materialize_document_numbering()

    validate_navigation!(source_blocks)

    {blocks, pages} =
      paginate_resolved(source_blocks, page_options, document, options)

    total_pages =
      length(pages)

    section_contexts = section_page_contexts(pages)

    {document, rendered_pages} =
      pages
      |> Enum.with_index(1)
      |> Enum.reduce({document, []}, fn {page_spec, page_number}, {current_document, rendered} ->
        placements = page_spec.placements
        page_options = page_spec.options
        render_options = page_spec.render_options

        context =
          page_context(
            page_options,
            page_number,
            total_pages,
            placements,
            Enum.at(section_contexts, page_number - 1)
          )

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
        measurements:
          Enum.map(Enum.flat_map(pages, & &1.placements), fn placement ->
            Map.take(placement, [:id, :type, :page_number, :width, :height, :x, :y])
          end),
        rendered_pages: Enum.reverse(rendered_pages)
      }

    {document, report}
  end

  defp materialize_notes(blocks) do
    {_next, _notes, materialized} =
      Enum.reduce(blocks, {1, [], []}, fn
        %Block{type: :footnote, content: %{number: number, text: text}} = block,
        {next, notes, acc} ->
          assigned = if number == :auto, do: next, else: number
          next = max(next, assigned + 1)
          note = %{number: assigned, text: text}
          {next, notes ++ [note], acc ++ [%{block | content: note}]}

        %Block{type: :endnotes} = block, {next, notes, acc} ->
          title =
            Block.new(:heading, Keyword.get(block.options, :title, "Endnotes"),
              level: Keyword.get(block.options, :level, 2)
            )

          entries =
            Enum.map(notes, fn note ->
              Block.new(:paragraph, "#{note.number}. #{note.text}",
                size: Keyword.get(block.options, :size, 8),
                line_height: Keyword.get(block.options, :line_height, 10)
              )
            end)

          {next, notes, acc ++ [title | entries]}

        block, state ->
          {next, notes, acc} = state
          {next, notes, acc ++ [block]}
      end)

    materialized
  end

  defp materialize_document_numbering(blocks) do
    {numbered, _counters} =
      Enum.map_reduce(blocks, %{figure: 0, table: 0}, fn block, counters ->
        case {block.type, Keyword.get(block.options, :numbered, false)} do
          {:image, true} ->
            number = counters.figure + 1
            label = Keyword.get(block.options, :caption_label, "Figure")
            caption = Keyword.get(block.options, :caption, "")
            destination = Keyword.get(block.options, :destination, "figure-#{number}")

            block =
              %{
                block
                | options:
                    block.options
                    |> Keyword.put(:caption, numbered_caption(label, number, caption))
                    |> Keyword.put(:destination, destination)
                    |> Keyword.put(:number, number)
              }

            {block, %{counters | figure: number}}

          {:table, true} ->
            number = counters.table + 1
            label = Keyword.get(block.options, :caption_label, "Table")
            caption = Keyword.get(block.options, :caption, "")
            destination = Keyword.get(block.options, :destination, "table-#{number}")

            caption_block =
              Block.new(
                :paragraph,
                numbered_caption(label, number, caption),
                destination: destination,
                size: Keyword.get(block.options, :caption_size, 9),
                space_after: Keyword.get(block.options, :caption_space_after, 6),
                keep_together: true
              )

            {[caption_block, %{block | options: Keyword.put(block.options, :number, number)}],
             %{counters | table: number}}

          _other ->
            {block, counters}
        end
      end)

    List.flatten(numbered)
  end

  defp numbered_caption(label, number, ""), do: "#{label} #{number}"
  defp numbered_caption(label, number, caption), do: "#{label} #{number}. #{caption}"

  defp expand_blocks(blocks, section, options, document) do
    Enum.flat_map(blocks, fn
      %Block{type: :component, content: %{name: name, assigns: assigns}} = block ->
        case Map.fetch(document.components, name) do
          {:ok, renderer} ->
            renderer.(assigns)
            |> Map.fetch!(:blocks)
            |> Enum.reverse()
            |> Enum.map(fn child ->
              %{child | options: Keyword.merge(block.options, child.options)}
            end)
            |> expand_blocks(section, Keyword.merge(options, block.options), document)

          :error ->
            raise LayoutError,
              reason: :unknown_component,
              block_id: block.id,
              block_type: :component,
              metadata: %{component: name}
        end

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
            apply_style(block, document)
            | options:
                apply_style(block, document).options
                |> Keyword.put_new(:section, section)
                |> Keyword.put_new(:layout_options, options)
          }
        ]
    end)
  end

  defp apply_style(%Block{} = block, document) do
    named_style = Keyword.get(block.options, :style)
    type_style = Map.get(document.styles, block.type, [])

    selected_style =
      if is_atom(named_style), do: Map.get(document.styles, named_style, []), else: []

    %{
      block
      | options:
          Keyword.merge(
            type_style,
            Keyword.merge(selected_style, Keyword.delete(block.options, :style))
          )
    }
  end

  defp paginate_resolved(source_blocks, page_options, document, options) do
    if navigation_sensitive?(source_blocks) do
      paginate_until_navigation_stabilizes(source_blocks, page_options, document, options)
    else
      {source_blocks, paginate(source_blocks, page_options, document, options)}
    end
  end

  defp navigation_sensitive?(blocks) do
    Enum.any?(blocks, &(&1.type in [:table_of_contents, :reference]))
  end

  defp paginate_until_navigation_stabilizes(
         source_blocks,
         page_options,
         document,
         options
       ) do
    Enum.reduce_while(1..4, {%{}, nil, nil}, fn _pass, {page_map, _blocks, _pages} ->
      blocks = materialize_navigation(source_blocks, page_map)
      pages = paginate(blocks, page_options, document, options)
      next_page_map = destination_page_map(pages)

      if next_page_map == page_map do
        {:halt, {blocks, pages}}
      else
        {:cont, {next_page_map, blocks, pages}}
      end
    end)
    |> case do
      {blocks, pages} when is_list(blocks) ->
        {blocks, pages}

      {page_map, _blocks, _pages} ->
        blocks = materialize_navigation(source_blocks, page_map)
        {blocks, paginate(blocks, page_options, document, options)}
    end
  end

  defp destination_page_map(pages) do
    pages
    |> Enum.flat_map(& &1.placements)
    |> Enum.reduce(%{}, fn
      %{type: :heading, block: block, page_number: page_number}, acc ->
        case Keyword.get(block.options, :destination, true) do
          false -> acc
          true -> Map.put(acc, normalize_destination(block.id), page_number)
          destination -> Map.put(acc, normalize_destination(destination), page_number)
        end

      %{block: block, page_number: page_number}, acc ->
        case Keyword.get(block.options, :destination, false) do
          false -> acc
          destination -> Map.put(acc, normalize_destination(destination), page_number)
        end

      _placement, acc ->
        acc
    end)
  end

  defp materialize_navigation(blocks, page_map) do
    entries =
      blocks
      |> Enum.filter(&(&1.type == :heading))
      |> Enum.reject(&(Keyword.get(&1.options, :destination, true) == false))
      |> Enum.map(fn heading ->
        destination =
          case Keyword.get(heading.options, :destination, true) do
            true -> heading.id
            value -> value
          end

        {heading.content, Keyword.get(heading.options, :level, 1), destination}
      end)

    Enum.flat_map(blocks, fn
      %Block{type: :table_of_contents} = block ->
        title = Keyword.get(block.options, :title, "Contents")
        levels = Keyword.get(block.options, :levels, 1..6)
        entries = Enum.filter(entries, fn {_text, level, _destination} -> level in levels end)

        title_block =
          Block.new(
            :heading,
            title,
            Keyword.merge(block.options, destination: false, bookmark: false, level: 2)
          )

        entry_blocks =
          Enum.map(entries, fn {text, level, destination} ->
            page = Map.get(page_map, normalize_destination(destination), "?")
            indent = max(level - 1, 0) * Keyword.get(block.options, :indent, 14)
            leader = Keyword.get(block.options, :leader, ".")
            leader_count = max((58 - String.length(text) - indent) |> round(), 4)

            entry_options =
              Keyword.merge(block.options,
                destination: false,
                bookmark: false,
                link_to: destination,
                space_after: 2
              )
              |> Keyword.merge(
                block.options
                |> Keyword.get(:level_styles, %{})
                |> Map.new()
                |> Map.get(level, [])
              )

            entry_options =
              case Keyword.fetch(block.options, :x) do
                {:ok, x} -> Keyword.put(entry_options, :x, x + indent)
                :error -> Keyword.delete(entry_options, :x)
              end

            entry_text =
              case Keyword.get(block.options, :entry_formatter) do
                formatter when is_function(formatter, 1) ->
                  formatter.(%{
                    title: text,
                    level: level,
                    destination: destination,
                    page: page
                  })

                _formatter ->
                  "#{text} #{String.duplicate(leader, leader_count)} #{page}"
              end

            Block.new(:paragraph, entry_text, entry_options)
          end)

        [title_block | entry_blocks]

      %Block{type: :reference, content: destination} = block ->
        page = Map.get(page_map, normalize_destination(destination), "?")
        prefix = Keyword.get(block.options, :prefix, "See page ")

        text =
          case Keyword.get(block.options, :text) do
            nil -> "#{prefix}#{page}"
            template -> String.replace(template, "{page}", to_string(page))
          end

        [
          %{
            block
            | type: :paragraph,
              content: text,
              options: Keyword.put(block.options, :link_to, destination)
          }
        ]

      block ->
        [block]
    end)
  end

  defp resolve_section_template_options(block_options, document) do
    case Keyword.get(block_options, :template) do
      nil ->
        []

      template ->
        case Document.resolve_page_template(document, template) do
          {:ok, template_options} ->
            template_options

          :error ->
            raise PageTemplateError,
              reason: :unknown_template,
              template: template

          {:error, :cycle} ->
            raise PageTemplateError,
              reason: :template_cycle,
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
    |> Enum.reverse()
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

  defp place_block(%Block{type: :rich_text} = block, state) do
    state = maybe_page_break_before(block, state)
    lines = paragraph_lines(block, state)
    state = place_text_lines(block, lines, state)
    maybe_page_break_after(block, state)
  end

  defp place_block(%Block{type: type} = block, state) when type in [:grid, :columns] do
    state = maybe_page_break_before(block, state)
    height = block_height(block, state) + Keyword.get(block.options, :space_after, 10)
    ensure_fits_empty_page!(block, height, state)

    state =
      if height > available_height(state) and current_page_has_content?(state),
        do: next_page(state),
        else: state

    state =
      add_fragment(state, %{
        id: block.id,
        type: type,
        block: block,
        y: state.cursor_y,
        height: height
      })

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
            :none -> ""
            :unordered -> "•"
          end

        Block.new(
          :paragraph,
          if(marker == "", do: to_string(item), else: "#{marker} #{item}"),
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
    repeat_header = Keyword.get(block.options, :repeat_header, true)
    header = measure_table_row(block.content.columns, block, state, true)

    {rows, _active_spans} =
      Enum.map_reduce(block.content.rows, %{}, fn row, spans ->
        measure_table_row(row, block, state, false, spans)
      end)

    place_table_rows(rows, header, repeat_header, block, state, 1, true)
    |> then(&maybe_page_break_after(block, &1))
  end

  defp place_block(%Block{type: :footnote} = block, state) do
    size = Keyword.get(block.options, :size, 8)
    line_height = Keyword.get(block.options, :line_height, 10)
    text = "#{block.content.number}. #{block.content.text}"

    lines =
      TextWrapper.wrap(text,
        width: fragment_width(%{block: block}, state.page),
        font: metric_font_for_block(block, state.document),
        size: size,
        hyphenate: Keyword.get(block.options, :hyphenate, false)
      )

    place_footnote_lines(block, lines, state, true, line_height)
  end

  defp place_block(%Block{type: type} = block, state)
       when type in [:image, :svg, :chart, :qr_code, :barcode] do
    state = maybe_page_break_before(block, state)
    image_height = Keyword.get(block.options, :height, if(type == :chart, do: 180, else: 120))

    caption_height =
      if Keyword.has_key?(block.options, :caption),
        do: Keyword.get(block.options, :caption_line_height, 16),
        else: 0

    height = image_height + caption_height + Keyword.get(block.options, :space_after, 14)

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
        type: type,
        block: block,
        y: state.cursor_y,
        height: min(height, available_height(state)),
        image_height: image_height
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

  defp place_footnote_lines(_block, [], state, _first?, _line_height), do: state

  defp place_footnote_lines(block, lines, state, first?, line_height) do
    separator_height = if first?, do: Keyword.get(block.options, :separator_height, 16), else: 0
    capacity = floor(max(available_height(state) - separator_height, 0) / line_height)

    state =
      if capacity < 1 and current_page_has_content?(state),
        do: next_page(state),
        else: state

    capacity = max(floor(max(available_height(state) - separator_height, 0) / line_height), 1)
    {visible, remaining} = Enum.split(lines, capacity)
    height = length(visible) * line_height + separator_height
    y = state.bottom_y - height

    fragment = %{
      id: "#{block.id}-footnote-#{state.page_number}",
      type: :footnote,
      block: block,
      y: y + separator_height,
      separator_y: y,
      first?: first?,
      height: height,
      lines: visible
    }

    state = add_reserved_fragment(state, fragment, y)

    if remaining == [],
      do: state,
      else: place_footnote_lines(block, remaining, next_page(state), false, line_height)
  end

  defp add_reserved_fragment(state, fragment, new_bottom) do
    [page | remaining_pages] = state.pages
    page = %{page | placements: page.placements ++ [placement(fragment, state)]}

    %{state | pages: [page | remaining_pages], bottom_y: new_bottom}
  end

  defp place_table_rows([], _header, _repeat_header, _block, state, _part, _first), do: state

  defp place_table_rows(rows, header, repeat_header, block, state, part, first?) do
    include_header? = repeat_header or first?
    header_height = if include_header?, do: header.height, else: 0
    available = available_height(state)
    full_height = state.bottom_y - Page.content_top(state.page) - header_height
    first_group = Enum.take(rows, max(Map.get(hd(rows), :span_rows, 1), 1))
    first_group_height = Enum.sum(Enum.map(first_group, & &1.height))

    if current_page_has_content?(state) and first_group_height > available - header_height and
         first_group_height <= full_height do
      place_table_rows(rows, header, repeat_header, block, next_page(state), part, first?)
    else
      do_place_table_rows(rows, header, repeat_header, block, state, part, first?, header_height)
    end
  end

  defp do_place_table_rows(rows, header, repeat_header, block, state, part, first?, header_height) do
    include_header? = repeat_header or first?

    state =
      if header_height >= available_height(state) and current_page_has_content?(state),
        do: next_page(state),
        else: state

    {placed, remaining} = take_table_rows(rows, available_height(state) - header_height)

    {placed, remaining, state} =
      if placed == [],
        do: place_oversized_table_row(rows, header_height, block, state),
        else: {placed, remaining, state}

    fragment_rows = if include_header?, do: [header | placed], else: placed
    content_height = Enum.sum(Enum.map(fragment_rows, & &1.height))
    final? = remaining == []
    space_after = if final?, do: Keyword.get(block.options, :space_after, 14), else: 0

    state =
      add_fragment(state, %{
        id: "#{block.id}-part-#{part}",
        type: :table,
        block: block,
        y: state.cursor_y,
        height: content_height + space_after,
        rows: fragment_rows
      })

    if final?,
      do: state,
      else:
        place_table_rows(
          remaining,
          header,
          repeat_header,
          block,
          next_page(state),
          part + 1,
          false
        )
  end

  defp take_table_rows(rows, available) do
    take_table_row_groups(rows, available, [])
  end

  defp take_table_row_groups([], _available, taken), do: {Enum.reverse(taken), []}

  defp take_table_row_groups([row | _rest] = rows, available, taken) do
    group_size = max(Map.get(row, :span_rows, 1), 1)
    group = Enum.take(rows, group_size)
    group_height = Enum.sum(Enum.map(group, & &1.height))

    if length(group) == group_size and group_height <= available do
      take_table_row_groups(
        Enum.drop(rows, group_size),
        available - group_height,
        Enum.reverse(group, taken)
      )
    else
      {Enum.reverse(taken), rows}
    end
  end

  defp place_oversized_table_row([row | rest], header_height, block, state) do
    policy = Keyword.get(block.options, :row_split, :keep)
    full_height = state.bottom_y - Page.content_top(state.page) - header_height
    span_rows = max(Map.get(row, :span_rows, 1), 1)

    cond do
      span_rows > 1 ->
        group = Enum.take([row | rest], span_rows)
        group_height = Enum.sum(Enum.map(group, & &1.height))

        if length(group) == span_rows and group_height <= full_height do
          {group, Enum.drop([row | rest], span_rows), state}
        else
          raise TableError, reason: :row_too_large, block_id: block.id, row: row.index
        end

      row.height <= full_height ->
        {[row], rest, state}

      policy == :split ->
        line_height = table_line_height(block)
        padding = Keyword.get(block.options, :padding, 6)

        capacity =
          max(
            floor((max(available_height(state) - header_height, 1) - padding * 2) / line_height),
            1
          )

        {visible, continuation} = split_table_row(row, capacity, block)
        remaining = if continuation, do: [continuation | rest], else: rest
        {[visible], remaining, state}

      true ->
        raise TableError, reason: :row_too_large, block_id: block.id, row: row.index
    end
  end

  defp split_table_row(row, line_capacity, block) do
    {visible_cells, remaining_cells} =
      row.cells
      |> Enum.map(fn cell ->
        {visible, remaining} = Enum.split(cell.lines, line_capacity)
        {%{cell | lines: visible}, %{cell | lines: remaining}}
      end)
      |> Enum.unzip()

    visible = %{row | cells: visible_cells, height: table_row_height(visible_cells, block)}

    continuation =
      unless Enum.all?(remaining_cells, &(&1.lines == [])),
        do: %{row | cells: remaining_cells, height: table_row_height(remaining_cells, block)}

    {visible, continuation}
  end

  defp measure_table_row(cells, block, state, header?) do
    {row, _spans} = measure_table_row(cells, block, state, header?, %{})
    row
  end

  defp measure_table_row(cells, block, state, header?, active_spans) do
    widths = table_column_widths(block, state)
    padding = Keyword.get(block.options, :padding, 6)

    {wrapped, next_column, new_spans} =
      Enum.reduce(cells, {[], 0, %{}}, fn raw_cell, {measured, column, spans} ->
        cell = normalize_table_cell(raw_cell)
        column = next_available_column(column, active_spans)
        colspan = min(cell.colspan, max(length(widths) - column, 1))
        width = widths |> Enum.slice(column, colspan) |> Enum.sum()
        font_key = Keyword.get(block.options, :font, state.document.default_font)

        text_options = [
          width: max(width - padding * 2, 1),
          font: font_key,
          size: Keyword.get(block.options, :size, 9),
          hyphenate: Keyword.get(block.options, :hyphenate, false)
        ]

        text_options =
          case FontRegistry.fetch(state.document.font_registry, font_key) do
            {:ok, font} -> Keyword.put(text_options, :font_instance, font)
            :error -> text_options
          end

        lines = TextWrapper.wrap(table_cell_text(cell.content), text_options)

        measured_cell =
          cell
          |> Map.put(:lines, lines)
          |> Map.put(:column, column)
          |> Map.put(:colspan, colspan)

        spans =
          if cell.rowspan > 1 do
            Enum.reduce(column..(column + colspan - 1), spans, fn index, acc ->
              Map.put(acc, index, cell.rowspan - 1)
            end)
          else
            spans
          end

        {[measured_cell | measured], column + colspan, spans}
      end)

    _next_column = next_column
    wrapped = Enum.reverse(wrapped)

    active_spans =
      active_spans
      |> Enum.flat_map(fn
        {column, remaining} when remaining > 1 -> [{column, remaining - 1}]
        _entry -> []
      end)
      |> Map.new()
      |> Map.merge(new_spans)

    {
      %{
        cells: wrapped,
        height: table_row_height(wrapped, block),
        span_rows: Enum.max(Enum.map(wrapped, & &1.rowspan), fn -> 1 end),
        header?: header?,
        index: if(header?, do: 0, else: :body)
      },
      active_spans
    }
  end

  defp table_row_height(cells, block) do
    padding = Keyword.get(block.options, :padding, 6)
    minimum = Keyword.get(block.options, :row_height, 24)

    max(
      minimum,
      Enum.max(
        Enum.map(cells, fn cell ->
          (length(cell.lines) * table_line_height(block) + padding * 2) / cell.rowspan
        end),
        fn -> 1 end
      )
    )
  end

  defp normalize_table_cell(%{content: _content} = cell) do
    %{
      content: cell.content,
      colspan: Map.get(cell, :colspan, 1),
      rowspan: Map.get(cell, :rowspan, 1),
      align: Map.get(cell, :align),
      valign: Map.get(cell, :valign, :top),
      borders: Map.get(cell, :borders, :all),
      fill_color: Map.get(cell, :fill_color),
      color: Map.get(cell, :color)
    }
  end

  defp normalize_table_cell(content) do
    %{
      content: content,
      colspan: 1,
      rowspan: 1,
      align: nil,
      valign: nil,
      borders: :all,
      fill_color: nil,
      color: nil
    }
  end

  defp table_cell_text(%Block{content: content}), do: table_cell_text(content)

  defp table_cell_text(blocks) when is_list(blocks) do
    blocks
    |> Enum.map(&table_cell_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp table_cell_text(%{text: text}) when is_binary(text), do: text
  defp table_cell_text(nil), do: ""
  defp table_cell_text(content), do: to_string(content)

  defp next_available_column(column, spans) do
    if Map.has_key?(spans, column),
      do: next_available_column(column + 1, spans),
      else: column
  end

  defp table_line_height(block),
    do: Keyword.get(block.options, :cell_line_height, Keyword.get(block.options, :size, 9) * 1.3)

  defp table_column_widths(block, state) do
    count = max(length(block.content.columns), 1)
    width = fragment_width(%{block: block}, state.page)
    Keyword.get(block.options, :column_widths, List.duplicate(width / count, count))
  end

  defp place_children(children, state) do
    Enum.reduce(children, state, &place_block/2)
  end

  defp place_text_lines(block, lines, state) do
    line_height = line_height(block)
    padding = Keyword.get(block.options, :padding, 0)
    space_before = Keyword.get(block.options, :space_before, 0)
    space_after = Keyword.get(block.options, :space_after, default_space_after(block))

    required_height =
      length(lines) * line_height + padding * 2 + space_before + space_after

    full_page_height = state.bottom_y - Page.content_top(state.page)

    state =
      if Keyword.get(block.options, :keep_together, false) and
           required_height > available_height(state) and required_height <= full_page_height and
           current_page_has_content?(state) do
        next_page(state)
      else
        state
      end

    available_lines =
      max(
        floor(
          max(available_height(state) - space_before - space_after - padding * 2, 0) /
            line_height
        ),
        1
      )

    {visible, remaining} = Enum.split(lines, available_lines)

    {visible, remaining, state} =
      apply_widow_orphan_control(block, visible, remaining, lines, state)

    height = length(visible) * line_height + padding * 2 + space_before + space_after
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
    [page | remaining_pages] = state.pages
    page = %{page | placements: page.placements ++ [placement(fragment, state)]}

    %{
      state
      | pages: [page | remaining_pages],
        cursor_y: state.cursor_y + fragment.height
    }
  end

  defp next_page(%{pages: pages} = state) do
    new_page = Page.new(state.page_options)

    %{
      state
      | pages: [
          %{options: state.page_options, render_options: state.render_options, placements: []}
          | pages
        ],
        page_number: state.page_number + 1,
        page: new_page,
        cursor_y: Page.content_top(new_page),
        bottom_y: Page.content_bottom(new_page)
    }
  end

  defp available_height(state), do: max(state.bottom_y - state.cursor_y, 0)
  defp current_page_has_content?(state), do: hd(state.pages).placements != []

  defp placement(fragment, state) do
    fragment
    |> Map.put(:page_number, state.page_number)
    |> Map.put(:x, fragment_x(fragment, state.page))
    |> Map.put(:y, fragment_y(fragment))
    |> Map.put(:width, fragment_width(fragment, state.page))
    |> Map.put(:section, Keyword.get(fragment.block.options, :section))
  end

  defp fragment_x(%{block: block}, page),
    do: Keyword.get(block.options, :x, Page.content_left(page))

  defp fragment_y(%{block: block, y: flow_y}),
    do: Keyword.get(block.options, :y, flow_y)

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

      [page_spec | remaining_pages] = state.pages

      pages = [
        %{page_spec | options: new_page_options, render_options: new_render_options}
        | remaining_pages
      ]

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

  defp block_height(%Block{type: type} = block, state) when type in [:paragraph, :rich_text],
    do: length(paragraph_lines(block, state)) * line_height(block)

  defp block_height(%Block{type: :heading} = block, _state), do: line_height(block)
  defp block_height(%Block{type: :spacer, content: height}, _state), do: height

  defp block_height(%Block{type: :separator} = block, _state),
    do: Keyword.get(block.options, :height, 12)

  defp block_height(%Block{type: :image} = block, _state),
    do: Keyword.get(block.options, :height, 120)

  defp block_height(%Block{type: :svg} = block, _state),
    do: Keyword.get(block.options, :height, 120)

  defp block_height(%Block{type: :chart} = block, _state),
    do: Keyword.get(block.options, :height, 180)

  defp block_height(%Block{type: :qr_code} = block, _state),
    do: Keyword.get(block.options, :height, 120)

  defp block_height(%Block{type: :barcode} = block, _state),
    do: Keyword.get(block.options, :height, 72)

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

  defp block_height(
         %Block{type: :grid, content: %{columns: columns, cells: cells}} = block,
         _state
       ) do
    rows = ceil(length(cells) / columns)

    rows * Keyword.get(block.options, :cell_height, 74) +
      max(rows - 1, 0) * Keyword.get(block.options, :gap, 12)
  end

  defp block_height(
         %Block{type: :columns, content: %{count: count, paragraphs: paragraphs}} = block,
         state
       ) do
    gap = Keyword.get(block.options, :column_gap, Keyword.get(block.options, :gap, 18))

    width =
      (fragment_width(%{block: block}, state.page) -
         (count - 1) * gap) / count

    line_height = line_height(block)

    paragraphs
    |> Enum.map(fn paragraph ->
      TextWrapper.wrap(paragraph,
        width: width,
        font: metric_font_for_block(block, state.document),
        size: default_size(block)
      )
      |> length()
    end)
    |> Enum.chunk_every(ceil(length(paragraphs) / count))
    |> Enum.map(&Enum.sum/1)
    |> Enum.max(fn -> 1 end)
    |> Kernel.*(line_height)
    |> Kernel.+(max(ceil(length(paragraphs) / count) - 1, 0) * 8)
  end

  defp paragraph_lines(block, state) do
    padding = Keyword.get(block.options, :padding, 0)
    width = max(resolved_block_width(block, state.page) - padding * 2, 1)

    if block.type == :rich_text do
      rich_text_lines(block.content, block, width)
    else
      TextWrapper.wrap(
        block_text(block),
        width: width,
        font: metric_font_for_block(block, state.document),
        size: Keyword.get(block.options, :size, default_size(block)),
        hyphenate: Keyword.get(block.options, :hyphenate, false)
      )
    end
  end

  defp rich_text_lines(runs, block, width) do
    runs
    |> Enum.flat_map(fn %{text: text, options: options} ->
      ~r/\n|[^\S\n]+|[^\s]+/u
      |> Regex.scan(text)
      |> Enum.map(fn [token] -> %{text: token, options: options} end)
    end)
    |> Enum.reduce([[]], &append_rich_token(&2, &1, block, width))
    |> Enum.reverse()
    |> Enum.map(&Enum.reverse/1)
  end

  defp append_rich_token(lines, %{text: "\n"}, _block, _width), do: [[] | lines]

  defp append_rich_token([[] | _rest] = lines, %{text: text}, _block, _width)
       when text in [" ", "\t"],
       do: lines

  defp append_rich_token([line | rest] = lines, fragment, block, width) do
    cond do
      rich_line_width(Enum.reverse([fragment | line]), block) <= width ->
        [append_rich_fragment(line, fragment) | rest]

      fragment.text =~ ~r/^\s+$/u ->
        [[] | lines]

      line != [] ->
        append_rich_token([[] | lines], fragment, block, width)

      true ->
        fragment.text
        |> String.graphemes()
        |> Enum.reduce(lines, fn grapheme, current ->
          append_rich_token(current, %{fragment | text: grapheme}, block, width)
        end)
    end
  end

  defp append_rich_fragment([%{options: options, text: text} = last | rest], %{
         options: options,
         text: next
       }),
       do: [%{last | text: text <> next} | rest]

  defp append_rich_fragment(line, fragment), do: [fragment | line]

  defp rich_line_width(line, block) do
    Enum.reduce(line, 0, fn %{text: text, options: options}, total ->
      size = Keyword.get(options, :size, Keyword.get(block.options, :size, default_size(block)))
      font = Keyword.get(options, :font, Keyword.get(block.options, :font, :helvetica))
      weight = Keyword.get(options, :weight, Keyword.get(block.options, :weight, :regular))
      style = Keyword.get(options, :style, Keyword.get(block.options, :style, :normal))

      total +
        PaperForge.TextMetrics.line_width(text,
          font: builtin_metric_font(font, weight, style),
          size: size
        )
    end)
  end

  defp resolved_block_width(block, page) do
    case Keyword.get(block.options, :width, Page.content_width(page)) do
      :content -> Page.content_width(page)
      width -> width
    end
  end

  defp apply_widow_orphan_control(block, visible, remaining, lines, state) do
    min_top = Keyword.get(block.options, :min_lines_at_top, 2)
    min_bottom = Keyword.get(block.options, :min_lines_at_bottom, 2)

    cond do
      remaining != [] and length(visible) < min_top and current_page_has_content?(state) ->
        {next_visible, next_remaining} =
          Enum.split(
            lines,
            max(floor(available_height(next_page(state)) / line_height(block)), 1)
          )

        {next_visible, next_remaining, next_page(state)}

      remaining != [] and length(remaining) < min_bottom and length(visible) > min_top ->
        move = min(min_bottom - length(remaining), length(visible) - min_top)
        {kept, moved} = Enum.split(visible, length(visible) - move)
        {kept, moved ++ remaining, state}

      true ->
        {visible, remaining, state}
    end
  end

  defp block_text(%Block{content: content}), do: content

  defp line_height(block),
    do: Keyword.get(block.options, :line_height, default_size(block) * 1.35)

  defp default_size(%Block{type: :heading, options: options}),
    do: 24 - (Keyword.get(options, :level, 1) - 1) * 2

  defp default_size(_block), do: 11
  defp default_space_after(%Block{type: :heading}), do: 10
  defp default_space_after(_block), do: 4

  defp page_context(page_options, page_number, total_pages, placements, section_context) do
    page = Page.new(page_options)
    heading = current_heading(placements)

    %PageContext{
      page_number: page_number,
      total_pages: total_pages,
      section_page_number: section_context.page_number,
      section_total_pages: section_context.total_pages,
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

  defp section_page_contexts(pages) do
    sections = Enum.map(pages, &current_section(&1.placements))
    totals = Enum.frequencies(sections)

    {contexts, _counts} =
      Enum.map_reduce(sections, %{}, fn section, counts ->
        page_number = Map.get(counts, section, 0) + 1

        {
          %{section: section, page_number: page_number, total_pages: Map.fetch!(totals, section)},
          Map.put(counts, section, page_number)
        }
      end)

    contexts
  end

  defp render_template(page, key, options, context) do
    case template_value(key, options, context) do
      nil -> page
      fun when is_function(fun, 2) -> fun.(page, context)
      text when is_binary(text) -> render_template_text(page, key, text, context)
    end
  end

  defp template_value(key, options, context) do
    variant_key =
      cond do
        context.page_number == 1 and Keyword.has_key?(options, :"first_#{key}") ->
          :"first_#{key}"

        context.page_number == context.total_pages and Keyword.has_key?(options, :"last_#{key}") ->
          :"last_#{key}"

        rem(context.page_number, 2) == 0 and Keyword.has_key?(options, :"even_#{key}") ->
          :"even_#{key}"

        rem(context.page_number, 2) == 1 and Keyword.has_key?(options, :"odd_#{key}") ->
          :"odd_#{key}"

        true ->
          key
      end

    Keyword.get(options, variant_key)
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

  defp destination_names(%Block{} = block) do
    block.options
    |> Keyword.get(:destination, false)
    |> case do
      false -> []
      destination -> [destination]
    end
  end

  defp link_targets(%Block{type: :container, children: children}) do
    Enum.flat_map(children, &link_targets/1)
  end

  defp link_targets(%Block{type: :reference, content: destination}), do: [destination]

  defp link_targets(%Block{} = block) do
    block.options
    |> Keyword.get(:link_to)
    |> List.wrap()
  end

  defp normalize_destination(destination) when is_atom(destination),
    do: Atom.to_string(destination)

  defp normalize_destination(destination), do: destination

  defp render_template_text(page, :header, text, context) do
    Page.text(page, interpolate_template_text(text, context),
      x: context.content_left,
      y: max(context.content_top - 28, 12),
      width: context.content_width,
      align: :center,
      size: 9
    )
  end

  defp render_template_text(page, :footer, text, context) do
    Page.text(page, interpolate_template_text(text, context),
      x: context.content_left,
      y: min(context.content_bottom + 24, context.page_height - 12),
      width: context.content_width,
      align: :center,
      size: 9
    )
  end

  defp interpolate_template_text(text, context) do
    text
    |> String.replace("{page}", Integer.to_string(context.page_number))
    |> String.replace("{total}", Integer.to_string(context.total_pages))
    |> String.replace("{section_page}", Integer.to_string(context.section_page_number))
    |> String.replace("{section_total}", Integer.to_string(context.section_total_pages))
  end

  defp render_placements(page, placements, context, document) do
    Enum.reduce(placements, page, fn placement, current_page ->
      render_placement(current_page, placement, context, document)
    end)
  end

  defp render_placement(
         page,
         %{type: :rich_text, block: block, y: y} = placement,
         _context,
         _document
       ) do
    padding = Keyword.get(block.options, :padding, 0)
    decorated_height = length(placement.lines) * line_height(block) + padding * 2

    page
    |> render_text_background(block, placement, y, decorated_height)
    |> render_rich_text_lines(
      placement.lines,
      placement.x + padding,
      y + padding,
      max(placement.width - padding * 2, 1),
      block
    )
    |> maybe_render_block_link(block, placement, y)
  end

  defp render_placement(page, %{type: type, block: block, y: y} = placement, _context, document)
       when type in [:paragraph, :heading] do
    text = Enum.join(placement.lines, "\n")
    level = Keyword.get(block.options, :level, 1)
    default_weight = if(type == :heading and level <= 2, do: :bold, else: :regular)
    size = Keyword.get(block.options, :size, default_size(block))

    destination =
      if type == :heading,
        do: Keyword.get(block.options, :destination, block.id),
        else: Keyword.get(block.options, :destination, false)

    page =
      if destination != false do
        page
        |> Page.destination(destination, y: y)
        |> then(fn destination_page ->
          if type == :heading,
            do: maybe_bookmark(destination_page, block, text, y),
            else: destination_page
        end)
      else
        page
      end

    padding = Keyword.get(block.options, :padding, 0)
    decorated_height = length(placement.lines) * line_height(block) + padding * 2

    page = render_text_background(page, block, placement, y, decorated_height)

    page =
      Page.text_box(page, text,
        x: placement.x + padding,
        y: y + padding,
        width: max(placement.width - padding * 2, 1),
        font: Keyword.get(block.options, :font, document.default_font),
        size: size,
        line_height: line_height(block),
        align: Keyword.get(block.options, :align, :left),
        color: Keyword.get(block.options, :color, PaperForge.Color.black()),
        weight: Keyword.get(block.options, :weight, default_weight),
        style: Keyword.get(block.options, :style, :normal)
      )

    maybe_render_block_link(page, block, placement, y)
  end

  defp render_placement(
         page,
         %{type: :footnote, block: block, y: y, lines: lines} = placement,
         _context,
         _document
       ) do
    page =
      if placement.first? do
        Page.line(page,
          x1: placement.x,
          y1: placement.separator_y + 3,
          x2: placement.x + min(placement.width, 120),
          y2: placement.separator_y + 3,
          width: 0.5,
          color: Keyword.get(block.options, :color, PaperForge.Color.gray(0.45))
        )
      else
        page
      end

    Page.text_box(page, Enum.join(lines, "\n"),
      x: placement.x,
      y: y,
      width: placement.width,
      height: length(lines) * Keyword.get(block.options, :line_height, 10),
      size: Keyword.get(block.options, :size, 8),
      line_height: Keyword.get(block.options, :line_height, 10),
      color: Keyword.get(block.options, :color, PaperForge.Color.gray(0.3))
    )
  end

  defp render_placement(
         page,
         %{type: :table, block: block, y: y, rows: measured_rows} = placement,
         _context,
         document
       ) do
    options =
      [
        x: Keyword.get(block.options, :x, Page.content_left(page)),
        y: y,
        width: placement.width,
        row_heights: Enum.map(measured_rows, & &1.height),
        line_height: table_line_height(block),
        padding: Keyword.get(block.options, :padding, 6),
        header: Keyword.get(block.options, :repeat_header, true),
        font: Keyword.get(block.options, :font, document.default_font),
        size: Keyword.get(block.options, :size, 9),
        column_widths: Keyword.get(block.options, :column_widths),
        header_fill_color:
          Keyword.get(block.options, :header_fill_color, PaperForge.Color.gray(0.92)),
        header_color: Keyword.get(block.options, :header_color, PaperForge.Color.black()),
        body_fill_color: Keyword.get(block.options, :body_fill_color),
        stripe_fill_color: Keyword.get(block.options, :stripe_fill_color),
        stroke_color: Keyword.get(block.options, :stroke_color, PaperForge.Color.gray(0.65)),
        line_width: Keyword.get(block.options, :line_width, 0.5),
        cell_align: Keyword.get(block.options, :cell_align, :left),
        cell_valign: Keyword.get(block.options, :cell_valign, :top),
        color: Keyword.get(block.options, :color, PaperForge.Color.black())
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    rows =
      Enum.map(measured_rows, fn row ->
        Enum.map(row.cells, fn cell ->
          cell
          |> Map.put(:content, Enum.join(cell.lines, "\n"))
          |> Map.delete(:lines)
        end)
      end)

    Page.table(page, rows, options)
  end

  defp render_placement(
         page,
         %{type: :chart, block: block, y: y, image_height: height},
         _context,
         _document
       ) do
    x = Keyword.get(block.options, :x, Page.content_left(page))
    width = Keyword.get(block.options, :width, Page.content_width(page))
    render_chart(page, block.content, x, y, width, height, block.options)
  end

  defp render_placement(page, placement, context, document),
    do: render_special_placement(page, placement, context, document)

  defp render_text_background(page, block, placement, y, height) do
    fill_color =
      Keyword.get(block.options, :fill_color, Keyword.get(block.options, :background_color))

    if not is_nil(fill_color) or Keyword.has_key?(block.options, :stroke_color) do
      Page.rectangle(page,
        x: placement.x,
        y: y,
        width: placement.width,
        height: height,
        fill: not is_nil(fill_color),
        stroke: Keyword.get(block.options, :line_width, 0) > 0,
        fill_color: fill_color || PaperForge.Color.white(),
        stroke_color: Keyword.get(block.options, :stroke_color, PaperForge.Color.gray(0.7)),
        line_width: Keyword.get(block.options, :line_width, 0.5)
      )
    else
      page
    end
  end

  defp maybe_render_block_link(page, block, placement, y) do
    case Keyword.get(block.options, :link_to) do
      nil ->
        page

      destination ->
        Page.link_to(page, destination,
          x: placement.x,
          y: y,
          width: placement.width,
          height: max(length(placement.lines) * line_height(block), line_height(block))
        )
    end
  end

  defp render_chart(page, series, x, y, width, height, options) do
    page =
      case Keyword.get(options, :background_color) do
        nil ->
          page

        color ->
          Page.rectangle(page,
            x: x,
            y: y,
            width: width,
            height: height,
            fill: true,
            stroke: false,
            fill_color: color
          )
      end

    case Keyword.get(options, :chart_type, :bar) do
      :bar ->
        render_bar_chart(page, series, x, y, width, height, options)

      type when type in [:line, :area, :scatter] ->
        render_cartesian_chart(page, series, x, y, width, height, type, options)

      type when type in [:pie, :donut] ->
        render_radial_chart(page, series, x, y, width, height, type, options)

      other ->
        raise ArgumentError, "unsupported chart type: #{inspect(other)}"
    end
  end

  defp render_bar_chart(page, series, x, y, width, height, options) do
    values = Enum.map(series, fn {_label, value} -> value end)
    max_value = max(Enum.max(values, fn -> 1 end), 1)
    padding = chart_padding(options)
    plot_x = x + padding
    plot_width = max(width - padding * 2, 1)
    gap = Keyword.get(options, :gap, 12)
    value_area = Keyword.get(options, :value_area, 22)
    value_gap = Keyword.get(options, :value_gap, 7)
    label_area = 18
    plot_height = max(height - padding * 2 - value_area - label_area, 1)
    bar_width = max((plot_width - gap * (length(values) - 1)) / max(length(values), 1), 8)
    colors = chart_colors(options)

    series
    |> Enum.with_index()
    |> Enum.reduce(page, fn {{label, value}, index}, current ->
      bar_height = plot_height * value / max_value
      bar_x = plot_x + index * (bar_width + gap)
      bar_y = y + padding + value_area + plot_height - bar_height

      current
      |> Page.rectangle(
        x: bar_x,
        y: bar_y,
        width: bar_width,
        height: bar_height,
        fill: true,
        stroke: false,
        fill_color: Enum.at(colors, rem(index, length(colors)))
      )
      |> maybe_chart_value(value, bar_x, max(bar_y - value_gap, y + padding), bar_width, options)
      |> Page.text(label,
        x: bar_x,
        y: y + height - padding - 8,
        width: bar_width,
        align: :center,
        size: 8,
        color: chart_label_color(options)
      )
    end)
  end

  defp render_cartesian_chart(page, series, x, y, width, height, type, options) do
    values = Enum.map(series, &elem(&1, 1))
    max_value = max(Enum.max(values, fn -> 1 end), 1)
    padding = chart_padding(options)
    plot_x = x + padding
    plot_width = max(width - padding * 2, 1)
    label_area = 18
    top_area = if Keyword.get(options, :show_values, true), do: 16, else: 4
    plot_height = max(height - padding * 2 - label_area - top_area, 1)
    step = if length(series) > 1, do: plot_width / (length(series) - 1), else: 0
    color = hd(chart_colors(options))

    points =
      series
      |> Enum.with_index()
      |> Enum.map(fn {{_label, value}, index} ->
        {plot_x + index * step,
         y + padding + top_area + plot_height - plot_height * value / max_value}
      end)

    page =
      if type == :area and points != [] do
        [{first_x, _} | _] = points
        {last_x, _} = List.last(points)

        segments =
          [{:move_to, first_x, y + padding + top_area + plot_height}] ++
            Enum.map(points, fn {px, py} -> {:line_to, px, py} end) ++
            [{:line_to, last_x, y + padding + top_area + plot_height}, :close]

        Page.path(page, segments,
          fill: true,
          stroke: false,
          fill_color: Keyword.get(options, :fill_color, color)
        )
      else
        page
      end

    page =
      if type in [:line, :area] and length(points) > 1 do
        segments =
          points
          |> Enum.with_index()
          |> Enum.map(fn {{px, py}, index} ->
            if index == 0, do: {:move_to, px, py}, else: {:line_to, px, py}
          end)

        Page.path(page, segments,
          fill: false,
          stroke: true,
          stroke_color: color,
          line_width: Keyword.get(options, :line_width, 2)
        )
      else
        page
      end

    radius = Keyword.get(options, :point_radius, 3.5)

    series
    |> Enum.zip(points)
    |> Enum.reduce(page, fn {{label, value}, {px, py}}, current ->
      current
      |> Page.circle(x: px, y: py, radius: radius, fill: true, stroke: false, fill_color: color)
      |> maybe_chart_value(value, px - 20, max(py - 13, y + padding), 40, options)
      |> Page.text(label,
        x: px - 24,
        y: y + height - padding - 8,
        width: 48,
        align: :center,
        size: 8,
        color: chart_label_color(options)
      )
    end)
  end

  defp render_radial_chart(page, series, x, y, width, height, type, options) do
    total = series |> Enum.map(&max(elem(&1, 1), 0)) |> Enum.sum()
    colors = chart_colors(options)
    padding = chart_padding(options)
    inner_width = max(width - padding * 2, 1)
    inner_height = max(height - padding * 2, 1)
    radius = max(min(inner_width * 0.28, inner_height * 0.42), 10)
    center_x = x + padding + radius
    center_y = y + padding + inner_height / 2

    {page, _angle} =
      series
      |> Enum.with_index()
      |> Enum.reduce({page, -90.0}, fn {{_label, value}, index}, {current, angle} ->
        sweep = if total > 0, do: max(value, 0) / total * 360, else: 0
        color = Enum.at(colors, rem(index, length(colors)))
        {draw_wedge(current, center_x, center_y, radius, angle, sweep, color), angle + sweep}
      end)

    page =
      if type == :donut do
        Page.circle(page,
          x: center_x,
          y: center_y,
          radius: radius * Keyword.get(options, :inner_radius, 0.55),
          fill: true,
          stroke: false,
          fill_color: Keyword.get(options, :background_color, PaperForge.Color.white())
        )
      else
        page
      end

    legend_x = center_x + radius + 24
    legend_width = max(x + width - padding - legend_x, 60)

    series
    |> Enum.with_index()
    |> Enum.reduce(page, fn {{label, value}, index}, current ->
      row_y = y + padding + 6 + index * 18
      color = Enum.at(colors, rem(index, length(colors)))

      current
      |> Page.circle(
        x: legend_x,
        y: row_y + 4,
        radius: 4,
        fill: true,
        stroke: false,
        fill_color: color
      )
      |> Page.text("#{label}  #{value}",
        x: legend_x + 11,
        y: row_y,
        width: legend_width,
        size: 8,
        color: chart_label_color(options)
      )
    end)
  end

  defp draw_wedge(page, cx, cy, radius, start_angle, sweep, color) do
    steps = max(ceil(abs(sweep) / 12), 1)

    arc =
      Enum.map(0..steps, fn step ->
        angle = (start_angle + sweep * step / steps) * :math.pi() / 180
        {:line_to, cx + radius * :math.cos(angle), cy + radius * :math.sin(angle)}
      end)

    Page.path(page, [{:move_to, cx, cy} | arc] ++ [:close],
      fill: true,
      stroke: false,
      fill_color: color
    )
  end

  defp maybe_chart_value(page, value, x, y, width, options) do
    if Keyword.get(options, :show_values, true),
      do:
        Page.text(page, to_string(value),
          x: x,
          y: y,
          width: width,
          align: :center,
          size: 8,
          color: chart_label_color(options)
        ),
      else: page
  end

  defp chart_label_color(options),
    do: Keyword.get(options, :label_color, PaperForge.Color.black())

  defp chart_padding(options), do: max(Keyword.get(options, :chart_padding, 12), 0)

  defp chart_colors(options) do
    case Keyword.get(options, :colors) do
      colors when is_list(colors) and colors != [] ->
        colors

      _ ->
        [
          Keyword.get(options, :color, PaperForge.Color.rgb255(15, 143, 131)),
          PaperForge.Color.rgb255(23, 107, 135),
          PaperForge.Color.rgb255(232, 173, 53),
          PaperForge.Color.rgb255(231, 101, 84),
          PaperForge.Color.rgb255(102, 83, 165),
          PaperForge.Color.rgb255(74, 154, 195)
        ]
    end
  end

  defp render_special_placement(
         page,
         %{type: :svg, block: block, y: y, image_height: height},
         _context,
         _document
       ) do
    PaperForge.SVG.render(page, block.content,
      x: Keyword.get(block.options, :x, Page.content_left(page)),
      y: y,
      width: Keyword.get(block.options, :width, Page.content_width(page)),
      height: height
    )
  end

  defp render_special_placement(
         page,
         %{type: :qr_code, block: block, y: y, image_height: height},
         _context,
         _document
       ) do
    matrix =
      Qiroex.to_matrix!(block.content,
        level: Keyword.get(block.options, :level, :m),
        quiet_zone: 4
      )

    count = length(matrix)
    size = min(Keyword.get(block.options, :width, height), height)
    module_size = size / count
    x = Keyword.get(block.options, :x, Page.content_left(page))
    color = Keyword.get(block.options, :color, PaperForge.Color.black())

    matrix
    |> Enum.with_index()
    |> Enum.reduce(page, fn {row, row_index}, current ->
      row
      |> Enum.with_index()
      |> Enum.reduce(current, fn
        {1, column_index}, qr_page ->
          Page.rectangle(qr_page,
            x: x + column_index * module_size,
            y: y + row_index * module_size,
            width: module_size + 0.01,
            height: module_size + 0.01,
            fill: true,
            fill_color: color,
            stroke: false
          )

        {_light, _column_index}, qr_page ->
          qr_page
      end)
    end)
  end

  defp render_special_placement(
         page,
         %{type: :image, block: block, y: y, image_height: image_height},
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

    image_options =
      block.options
      |> Keyword.take([:fit, :focal_point, :align, :valign, :origin])
      |> Keyword.merge(x: x, y: y, width: width, height: image_height)

    page =
      case Keyword.get(block.options, :destination) do
        nil -> page
        destination -> Page.destination(page, destination, y: y)
      end

    page
    |> Page.image(block.content, image_options)
    |> maybe_render_caption(block, y + image_height + 4, width, x)
  end

  defp render_special_placement(
         page,
         %{type: :barcode, block: block, y: y, image_height: height},
         _context,
         _document
       ) do
    elements = PaperForge.Barcode.interleaved_2_of_5(block.content)
    width = Keyword.get(block.options, :width, Page.content_width(page))
    x = Keyword.get(block.options, :x, Page.content_left(page))
    unit = width / Enum.sum(Enum.map(elements, &elem(&1, 1)))

    {page, _} =
      Enum.reduce(elements, {page, x}, fn {bar?, units}, {current, cursor} ->
        element_width = units * unit

        current =
          if bar?,
            do:
              Page.rectangle(current,
                x: cursor,
                y: y,
                width: element_width,
                height: height - 14,
                fill: true,
                fill_color: Keyword.get(block.options, :color, PaperForge.Color.black()),
                stroke: false
              ),
            else: current

        {current, cursor + element_width}
      end)

    Page.text(page, block.content, x: x, y: y + height - 2, width: width, align: :center, size: 9)
  end

  defp render_special_placement(
         page,
         %{type: :separator, block: block, y: y},
         _context,
         _document
       ) do
    Page.line(page,
      x1: Page.content_left(page),
      y1: y + Keyword.get(block.options, :height, 12) / 2,
      x2: Page.content_left(page) + Page.content_width(page),
      y2: y + Keyword.get(block.options, :height, 12) / 2,
      width: Keyword.get(block.options, :line_width, 1)
    )
  end

  defp render_special_placement(page, %{type: :spacer}, _context, _document), do: page

  defp render_special_placement(
         page,
         %{type: :grid, block: block, y: y},
         _context,
         document
       ) do
    %{columns: columns, cells: cells} = block.content
    gap = Keyword.get(block.options, :gap, 12)
    width = Keyword.get(block.options, :width, Page.content_width(page))
    cell_width = (width - (columns - 1) * gap) / columns
    cell_height = Keyword.get(block.options, :cell_height, 74)
    x = Keyword.get(block.options, :x, Page.content_left(page))

    cells
    |> Enum.with_index()
    |> Enum.reduce(page, fn {cell, index}, current ->
      column = rem(index, columns)
      row = div(index, columns)
      cell_x = x + column * (cell_width + gap)
      cell_y = y + row * (cell_height + gap)

      text =
        if is_list(cell),
          do:
            Enum.map_join(cell, "", fn
              %{text: text} -> text
              text -> to_string(text)
            end),
          else: to_string(cell)

      current
      |> Page.rectangle(
        x: cell_x,
        y: cell_y,
        width: cell_width,
        height: cell_height,
        fill: true,
        fill_color: Keyword.get(block.options, :fill_color, PaperForge.Color.gray(0.97)),
        stroke: true,
        stroke_color: Keyword.get(block.options, :stroke_color, PaperForge.Color.gray(0.82))
      )
      |> Page.text_box(text,
        x: cell_x + 10,
        y: cell_y + 10,
        width: cell_width - 20,
        height: cell_height - 20,
        size: Keyword.get(block.options, :size, 10),
        line_height: Keyword.get(block.options, :line_height, 13),
        font: Keyword.get(block.options, :font, document.default_font),
        weight: Keyword.get(block.options, :weight, :regular),
        style: Keyword.get(block.options, :style, :normal),
        color: Keyword.get(block.options, :color, PaperForge.Color.black()),
        align: Keyword.get(block.options, :align, :left)
      )
    end)
  end

  defp render_special_placement(page, %{type: :columns, block: block, y: y}, _context, document) do
    %{count: count, paragraphs: paragraphs} = block.content
    gap = Keyword.get(block.options, :column_gap, Keyword.get(block.options, :gap, 18))
    width = Keyword.get(block.options, :width, Page.content_width(page))
    column_width = (width - (count - 1) * gap) / count
    per_column = max(ceil(length(paragraphs) / count), 1)
    x = Keyword.get(block.options, :x, Page.content_left(page))

    paragraphs
    |> Enum.chunk_every(per_column)
    |> Enum.with_index()
    |> Enum.reduce(page, fn {column, index}, current ->
      {current, _cursor} =
        Enum.reduce(column, {current, y}, fn paragraph, {column_page, cursor} ->
          lines =
            TextWrapper.wrap(paragraph,
              width: column_width,
              font: metric_font_for_block(block, document),
              size: default_size(block)
            )

          line_height = line_height(block)

          {Page.text_box(column_page, paragraph,
             x: x + index * (column_width + gap),
             y: cursor,
             width: column_width,
             height: length(lines) * line_height,
             font: Keyword.get(block.options, :font, document.default_font),
             size: default_size(block),
             line_height: line_height,
             align: Keyword.get(block.options, :align, :left),
             color: Keyword.get(block.options, :color, PaperForge.Color.black()),
             weight: Keyword.get(block.options, :weight, :regular),
             style: Keyword.get(block.options, :style, :regular)
           ), cursor + length(lines) * line_height + 8}
        end)

      current
    end)
  end

  defp render_special_placement(
         page,
         %{type: :custom, block: block} = placement,
         context,
         _document
       ) do
    block.content.(
      page,
      %{
        context
        | block_x: placement.x,
          block_y: placement.y,
          block_width: placement.width,
          block_height: placement.height
      }
    )
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

  defp render_rich_text_lines(page, lines, x, y, width, block) do
    lines
    |> Enum.with_index()
    |> Enum.reduce(page, fn {runs, line_index}, current ->
      render_rich_text_line(current, runs, x, y + line_index * line_height(block), width, block)
    end)
  end

  defp render_rich_text_line(page, runs, x, y, width, block) do
    line_width = rich_line_width(runs, block)

    x =
      case Keyword.get(block.options, :align, :left) do
        :center -> x + max((width - line_width) / 2, 0)
        :right -> x + max(width - line_width, 0)
        _left -> x
      end

    Enum.reduce(runs, {page, x}, fn %{text: text, options: options}, {current, cursor} ->
      size = Keyword.get(options, :size, Keyword.get(block.options, :size, default_size(block)))
      font = Keyword.get(options, :font, Keyword.get(block.options, :font, :helvetica))
      weight = Keyword.get(options, :weight, Keyword.get(block.options, :weight, :regular))
      style = Keyword.get(options, :style, Keyword.get(block.options, :style, :regular))
      metric_font = builtin_metric_font(font, weight, style)
      next = cursor + PaperForge.TextMetrics.line_width(text, font: metric_font, size: size)

      current =
        Page.text(current, text,
          x: cursor,
          y: y,
          font: font,
          size: size,
          color:
            Keyword.get(
              options,
              :color,
              Keyword.get(block.options, :color, PaperForge.Color.black())
            ),
          weight: weight,
          style: style
        )

      current =
        case Keyword.get(options, :link) do
          nil ->
            current

          link ->
            Page.link(current, link,
              x: cursor,
              y: y,
              width: max(next - cursor, 1),
              height: line_height(block)
            )
        end

      {current, next}
    end)
    |> elem(0)
  end

  defp builtin_metric_font(:helvetica, :bold, style) when style in [:italic, :oblique],
    do: :helvetica_bold_oblique

  defp builtin_metric_font(:helvetica, :bold, _style), do: :helvetica_bold

  defp builtin_metric_font(:helvetica, _weight, style) when style in [:italic, :oblique],
    do: :helvetica_oblique

  defp builtin_metric_font(:times_roman, :bold, style) when style in [:italic, :oblique],
    do: :times_bold_italic

  defp builtin_metric_font(:times_roman, :bold, _style), do: :times_bold

  defp builtin_metric_font(:times_roman, _weight, style) when style in [:italic, :oblique],
    do: :times_italic

  defp builtin_metric_font(:courier, :bold, style) when style in [:italic, :oblique],
    do: :courier_bold_oblique

  defp builtin_metric_font(:courier, :bold, _style), do: :courier_bold

  defp builtin_metric_font(:courier, _weight, style) when style in [:italic, :oblique],
    do: :courier_oblique

  defp builtin_metric_font(font, _weight, _style), do: font

  defp metric_font_for_block(block, document) do
    font = Keyword.get(block.options, :font, document.default_font)
    level = Keyword.get(block.options, :level, 1)

    default_weight =
      if(block.type == :heading and level <= 2, do: :bold, else: :regular)

    metric_key =
      builtin_metric_font(
        font,
        Keyword.get(block.options, :weight, default_weight),
        Keyword.get(block.options, :style, :regular)
      )

    case FontRegistry.fetch(document.font_registry, metric_key) do
      {:ok, registered} -> registered
      :error -> metric_key
    end
  end
end
