defmodule PaperForge.Flow do
  @moduledoc """
  Builder for unified document layout blocks.
  """

  alias PaperForge.Layout.Block

  defstruct blocks: []

  @type t :: %__MODULE__{blocks: [Block.t()]}

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @spec heading(t(), binary(), keyword()) :: t()
  def heading(%__MODULE__{} = flow, text, options \\ []) when is_binary(text) do
    put_block(flow, Block.new(:heading, text, Keyword.put_new(options, :level, 1)))
  end

  @spec paragraph(t(), binary(), keyword()) :: t()
  def paragraph(%__MODULE__{} = flow, text, options \\ []) when is_binary(text) do
    put_block(flow, Block.new(:paragraph, text, options))
  end

  @doc """
  Adds a paragraph made of inline text runs.

  Each run is either a string or a `{text, options}` tuple. Run options can
  override `:font`, `:size`, `:color`, `:weight`, `:style`, and `:link`.
  """
  @spec rich_text(t(), [binary() | {binary(), keyword()}], keyword()) :: t()
  def rich_text(%__MODULE__{} = flow, runs, options \\ []) when is_list(runs) do
    put_block(flow, Block.new(:rich_text, normalize_runs!(runs), options))
  end

  @spec image(t(), binary(), keyword()) :: t()
  def image(%__MODULE__{} = flow, source, options \\ []) when is_binary(source) do
    put_block(flow, Block.new(:image, source, options))
  end

  @doc """
  Adds an SVG fragment rendered as native PDF vectors.

  The renderer supports paths, Bézier curves, groups, affine transforms,
  `viewBox`, clip paths, inherited presentation attributes, and the common
  geometric elements.
  """
  @spec svg(t(), binary(), keyword()) :: t()
  def svg(%__MODULE__{} = flow, source, options \\ []) when is_binary(source) do
    put_block(flow, Block.new(:svg, source, options))
  end

  @doc "Adds a measured scientific expression from `PaperForge.Math` AST."
  @spec math(t(), PaperForge.Math.ast(), keyword()) :: t()
  def math(%__MODULE__{} = flow, ast, options \\ []) do
    {_width, measured_height} = PaperForge.Math.measure(ast, options)
    height = Keyword.get(options, :height, measured_height + 8)

    custom(
      flow,
      fn page, context ->
        PaperForge.Math.render(page, ast,
          x: context.block_x,
          y: context.block_y,
          size: Keyword.get(options, :size, 14),
          color: Keyword.get(options, :color, PaperForge.Color.black())
        )
      end,
      Keyword.put(options, :height, height)
    )
  end

  @doc "Adds a native vector chart from `{label, value}` pairs. Supports `:bar`, `:line`, `:area`, `:scatter`, `:pie`, and `:donut` through `:chart_type`."
  @spec chart(t(), [{binary(), number()}], keyword()) :: t()
  def chart(%__MODULE__{} = flow, series, options \\ []) when is_list(series) do
    put_block(flow, Block.new(:chart, series, options))
  end

  @doc "Adds a scan-ready QR code rendered as PDF vector modules."
  @spec qr_code(t(), binary(), keyword()) :: t()
  def qr_code(%__MODULE__{} = flow, data, options \\ []) when is_binary(data) do
    put_block(flow, Block.new(:qr_code, data, options))
  end

  @doc "Adds a scan-ready Interleaved 2 of 5 numeric barcode."
  @spec barcode(t(), binary(), keyword()) :: t()
  def barcode(%__MODULE__{} = flow, data, options \\ []) when is_binary(data) do
    put_block(flow, Block.new(:barcode, data, options))
  end

  @spec table(t(), [term()], [[term()]], keyword()) :: t()
  def table(%__MODULE__{} = flow, columns, rows, options \\ [])
      when is_list(columns) and is_list(rows) do
    put_block(flow, Block.new(:table, %{columns: columns, rows: rows}, options))
  end

  @doc """
  Builds a composable table cell.

  Content can be a scalar value, a layout block, or a list of layout blocks.
  Options include `:colspan`, `:rowspan`, `:align`, `:valign`, `:borders`,
  `:fill_color`, and `:color`.
  """
  @spec cell(term(), keyword()) :: map()
  def cell(content, options \\ []) when is_list(options) do
    colspan = Keyword.get(options, :colspan, 1)
    rowspan = Keyword.get(options, :rowspan, 1)

    unless is_integer(colspan) and colspan > 0 and is_integer(rowspan) and rowspan > 0 do
      raise ArgumentError, "table cell colspan and rowspan must be positive integers"
    end

    %{
      content: content,
      colspan: colspan,
      rowspan: rowspan,
      align: Keyword.get(options, :align),
      valign: Keyword.get(options, :valign, :top),
      borders: Keyword.get(options, :borders, :all),
      fill_color: Keyword.get(options, :fill_color),
      color: Keyword.get(options, :color)
    }
  end

  @doc "Adds an automatic table of contents for headings in this flow."
  @spec table_of_contents(t(), keyword()) :: t()
  def table_of_contents(%__MODULE__{} = flow, options \\ []) do
    put_block(flow, Block.new(:table_of_contents, nil, options))
  end

  @doc "Adds a page-aware internal cross-reference to a heading or named destination."
  @spec reference(t(), binary() | atom(), keyword()) :: t()
  def reference(%__MODULE__{} = flow, destination, options \\ [])
      when is_binary(destination) or is_atom(destination) do
    put_block(flow, Block.new(:reference, destination, options))
  end

  @doc "Adds a reusable document component registered with `PaperForge.component/3`."
  @spec component(t(), atom(), map() | keyword(), keyword()) :: t()
  def component(%__MODULE__{} = flow, name, assigns \\ %{}, options \\ [])
      when is_atom(name) and (is_map(assigns) or is_list(assigns)) do
    put_block(flow, Block.new(:component, %{name: name, assigns: Map.new(assigns)}, options))
  end

  @doc """
  Adds a simple responsive grid. Cells accept strings or inline-run lists.

  The grid is intentionally flow-native: it calculates its own height and
  moves as a single block when necessary.
  """
  @spec grid(t(), pos_integer(), [term()], keyword()) :: t()
  def grid(%__MODULE__{} = flow, columns, cells, options \\ [])
      when is_integer(columns) and columns > 0 and is_list(cells) do
    put_block(flow, Block.new(:grid, %{columns: columns, cells: cells}, options))
  end

  @doc "Adds a multi-column text section with balanced sequential columns."
  @spec columns(t(), pos_integer(), [binary()], keyword()) :: t()
  def columns(%__MODULE__{} = flow, count, paragraphs, options \\ [])
      when is_integer(count) and count > 0 and is_list(paragraphs) do
    put_block(flow, Block.new(:columns, %{count: count, paragraphs: paragraphs}, options))
  end

  @spec list(t(), [term()], keyword()) :: t()
  def list(%__MODULE__{} = flow, items, options \\ []) when is_list(items) do
    put_block(flow, Block.new(:list, items, options))
  end

  @doc "Adds a footnote reserved at the bottom of its flow page."
  @spec footnote(t(), pos_integer(), binary(), keyword()) :: t()
  def footnote(%__MODULE__{} = flow, number, text, options)
      when is_integer(number) and number > 0 and is_binary(text) do
    flow
    |> maybe_append_footnote_marker(number, options)
    |> put_block(Block.new(:footnote, %{number: number, text: text}, options))
  end

  @spec footnote(t(), pos_integer(), binary()) :: t()
  def footnote(%__MODULE__{} = flow, number, text)
      when is_integer(number) and number > 0 and is_binary(text),
      do: footnote(flow, number, text, [])

  @spec footnote(t(), binary(), keyword()) :: t()
  def footnote(%__MODULE__{} = flow, text, options) when is_binary(text) do
    number = Enum.count(flow.blocks, &(&1.type == :footnote)) + 1
    footnote(flow, number, text, options)
  end

  @spec footnote(t(), binary()) :: t()
  def footnote(%__MODULE__{} = flow, text), do: footnote(flow, text, [])

  @doc "Adds an automatically numbered endnotes section."
  @spec endnotes(t(), [{pos_integer(), binary()}], keyword()) :: t()
  def endnotes(%__MODULE__{} = flow, notes, options \\ []) do
    put_block(flow, Block.new(:endnotes, notes, options))
  end

  @spec spacer(t(), number(), keyword()) :: t()
  def spacer(%__MODULE__{} = flow, height, options \\ [])
      when is_number(height) and height >= 0 do
    put_block(flow, Block.new(:spacer, height, options))
  end

  @spec separator(t(), keyword()) :: t()
  def separator(%__MODULE__{} = flow, options \\ []) do
    put_block(flow, Block.new(:separator, nil, options))
  end

  @spec page_break(t()) :: t()
  def page_break(%__MODULE__{} = flow) do
    put_block(flow, Block.new(:page_break, nil, []))
  end

  @spec keep_together(t(), (t() -> t()) | Block.t()) :: t()
  def keep_together(%__MODULE__{} = flow, %Block{} = block) do
    put_block(flow, %{block | options: Keyword.put(block.options, :keep_together, true)})
  end

  def keep_together(%__MODULE__{} = flow, fun) when is_function(fun, 1) do
    nested_flow =
      __MODULE__.new()
      |> fun.()

    put_block(
      flow,
      Block.new(:container, nil,
        keep_together: true,
        children: Enum.reverse(nested_flow.blocks)
      )
    )
  end

  @spec custom(
          t(),
          (PaperForge.Page.t(), PaperForge.PageContext.t() -> PaperForge.Page.t()),
          keyword()
        ) :: t()
  def custom(%__MODULE__{} = flow, fun, options \\ []) when is_function(fun, 2) do
    put_block(flow, Block.new(:custom, fun, options))
  end

  @spec section(t(), atom(), keyword(), (t() -> t())) :: t()
  def section(%__MODULE__{} = flow, section_id, options, fun)
      when is_atom(section_id) and is_list(options) and is_function(fun, 1) do
    nested_flow =
      __MODULE__.new()
      |> fun.()

    block =
      Block.new(:section, section_id,
        children: Enum.reverse(nested_flow.blocks),
        title: Keyword.get(options, :title),
        page_break_before: Keyword.get(options, :page_break_before, false),
        page_break_after: Keyword.get(options, :page_break_after, false),
        page_options: Keyword.get(options, :page_options, []),
        template: Keyword.get(options, :template),
        header: Keyword.get(options, :header),
        footer: Keyword.get(options, :footer)
      )

    put_block(flow, block)
  end

  defp put_block(%__MODULE__{} = flow, %Block{} = block) do
    %{flow | blocks: [block | flow.blocks]}
  end

  defp maybe_append_footnote_marker(flow, _number, options)
       when not is_list(options),
       do: flow

  defp maybe_append_footnote_marker(%__MODULE__{} = flow, number, options) do
    if Keyword.get(options, :marker, true) do
      marker = Keyword.get(options, :marker_text, "[#{number}]")
      %{flow | blocks: append_marker_to_latest(flow.blocks, marker)}
    else
      flow
    end
  end

  defp append_marker_to_latest(
         [%Block{type: type, content: content} = block | rest],
         marker
       )
       when type in [:paragraph, :heading] and is_binary(content) do
    [%{block | content: content <> marker} | rest]
  end

  defp append_marker_to_latest(
         [%Block{type: :rich_text, content: runs} = block | rest],
         marker
       ) do
    marker_run = %{text: marker, options: [size: 7, baseline_shift: 3]}
    [%{block | content: runs ++ [marker_run]} | rest]
  end

  defp append_marker_to_latest(
         [%Block{type: :table, content: %{rows: rows} = content} = block | rest],
         marker
       ) do
    updated_rows =
      List.update_at(rows, -1, fn row ->
        List.update_at(row, -1, &(to_string(&1) <> marker))
      end)

    [%{block | content: %{content | rows: updated_rows}} | rest]
  end

  defp append_marker_to_latest(blocks, _marker), do: blocks

  defp normalize_runs!(runs) do
    Enum.map(runs, fn
      text when is_binary(text) ->
        %{text: text, options: []}

      {text, options} when is_binary(text) and is_list(options) ->
        %{text: text, options: options}

      run ->
        raise ArgumentError,
              "rich text runs must be strings or {text, options}, got: #{inspect(run)}"
    end)
  end
end
