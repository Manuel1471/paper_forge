defmodule PaperForge.Math do
  @moduledoc """
  Math AST and native PDF renderer for scientific expressions.

  The AST is independent from any input notation and can represent symbols,
  rows, fractions, roots, matrices, superscripts, subscripts, and integrals.

  The default is 11-point Times Roman. All internal spacing and strokes scale
  with `:size`; rows align on the mathematical axis and matrix rows use their
  individual measured heights. `measure/2` and `render/3` share these metrics.
  """

  alias PaperForge.{Page, TextMetrics}

  @type ast ::
          {:symbol, binary()}
          | {:row, [ast()]}
          | {:fraction, ast(), ast()}
          | {:root, ast(), ast() | nil}
          | {:matrix, [[ast()]]}
          | {:superscript, ast(), ast()}
          | {:subscript, ast(), ast()}
          | {:integral, ast() | nil, ast() | nil, ast(), binary()}

  @spec symbol(term()) :: ast()
  def symbol(value), do: {:symbol, to_string(value)}
  @spec row([ast()]) :: ast()
  def row(items) when is_list(items), do: {:row, items}
  @spec fraction(ast(), ast()) :: ast()
  def fraction(numerator, denominator), do: {:fraction, numerator, denominator}
  @spec root(ast(), ast() | nil) :: ast()
  def root(value, index \\ nil), do: {:root, value, index}
  @spec matrix([[ast()]]) :: ast()
  def matrix(rows) when is_list(rows), do: {:matrix, rows}
  @spec superscript(ast(), ast()) :: ast()
  def superscript(base, exponent), do: {:superscript, base, exponent}
  @spec subscript(ast(), ast()) :: ast()
  def subscript(base, subscript), do: {:subscript, base, subscript}
  @spec integral(ast() | nil, ast() | nil, ast(), binary()) :: ast()
  def integral(lower, upper, body, variable \\ "x"), do: {:integral, lower, upper, body, variable}

  @doc "Returns the measured width and height of an expression."
  @spec measure(ast(), keyword()) :: {number(), number()}
  def measure(ast, options \\ []) do
    size = size!(options)
    do_measure(ast, size)
  end

  @doc "Renders a Math AST at top-left page coordinates."
  @spec render(Page.t(), ast(), keyword()) :: Page.t()
  def render(%Page{} = page, ast, options) do
    x = Keyword.fetch!(options, :x)
    y = Keyword.fetch!(options, :y)
    size = size!(options)
    color = Keyword.get(options, :color, PaperForge.Color.black())
    {page, _width} = draw(page, ast, x, y, size, color)
    page
  end

  defp size!(options) do
    size = Keyword.get(options, :size, 11)

    if is_number(size) and size > 0,
      do: size,
      else: raise(ArgumentError, "math size must be positive")
  end

  defp do_measure({:symbol, text}, size),
    do:
      {max(TextMetrics.line_width(text, font: :times_roman, size: size), size * 0.4), size * 1.25}

  defp do_measure({:row, items}, size) do
    measurements = Enum.map(items, &do_measure(&1, size))
    gaps = max(length(items) - 1, 0) * size * 0.18

    above = Enum.map(items, &axis(&1, size)) |> Enum.max(fn -> size * 0.68 end)

    below =
      Enum.zip(items, measurements)
      |> Enum.map(fn {item, {_, height}} -> height - axis(item, size) end)
      |> Enum.max(fn -> size * 0.57 end)

    {Enum.sum(Enum.map(measurements, &elem(&1, 0))) + gaps, above + below}
  end

  defp do_measure({:fraction, numerator, denominator}, size) do
    {nw, nh} = do_measure(numerator, size * 0.82)
    {dw, dh} = do_measure(denominator, size * 0.82)
    gap = size * 0.16
    {max(nw, dw) + size * 0.35, nh + dh + gap * 2}
  end

  defp do_measure({:root, value, index}, size) do
    {width, height} = do_measure(value, size)
    index_width = if(index, do: elem(do_measure(index, size * 0.55), 0), else: 0)
    {width + size * 0.75 + index_width, height + root_top_clearance(value, size) + size * 0.3}
  end

  defp do_measure({:matrix, rows}, size) do
    columns = rows |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)

    cell_width =
      rows
      |> List.flatten()
      |> Enum.map(&(elem(do_measure(&1, size * 0.8), 0) + size * 0.45))
      |> Enum.max(fn -> size end)

    {columns * cell_width + size * 0.8, Enum.sum(matrix_row_heights(rows, size)) + size * 0.35}
  end

  defp do_measure({kind, base, script}, size) when kind in [:superscript, :subscript] do
    {bw, bh} = do_measure(base, size)
    {sw, sh} = do_measure(script, size * 0.6)

    {bw + script_gap(size) + sw,
     if(kind == :superscript, do: bh + size * 0.25, else: max(bh, sh + size * 0.55))}
  end

  defp do_measure({:integral, lower, upper, body, variable}, size) do
    {bw, bh} = do_measure(body, size)
    {lw, _} = if(lower, do: do_measure(lower, size * 0.55), else: {0, 0})
    {uw, _} = if(upper, do: do_measure(upper, size * 0.55), else: {0, 0})
    operator_width = max(size * 1.55, size * 1.3 + max(lw, uw))

    {dw, _} = do_measure({:symbol, " d#{variable}"}, size)
    {operator_width + bw + dw + size * 0.12, max(bh + size * 0.55, size * 2.55)}
  end

  defp draw(page, {:symbol, text}, x, y, size, color) do
    {width, _height} = do_measure({:symbol, text}, size)

    {Page.text(page, text,
       x: x,
       y: y + size,
       size: size,
       font: :times_roman,
       color: color,
       origin: :top_left
     ), width}
  end

  defp draw(page, {:row, items}, x, y, size, color) do
    row_axis = items |> Enum.map(&axis(&1, size)) |> Enum.max(fn -> size * 0.68 end)

    last_index = length(items) - 1

    items
    |> Enum.with_index()
    |> Enum.reduce({page, 0}, fn {item, index}, {current, offset} ->
      item_y = y + row_axis - axis(item, size)
      {current, width} = draw(current, item, x + offset, item_y, size, color)
      gap = if index < last_index, do: size * 0.18, else: 0
      {current, offset + width + gap}
    end)
  end

  defp draw(page, {:fraction, numerator, denominator} = ast, x, y, size, color) do
    {width, _height} = do_measure(ast, size)
    {nw, nh} = do_measure(numerator, size * 0.82)
    {dw, _dh} = do_measure(denominator, size * 0.82)
    gap = size * 0.16
    {page, _} = draw(page, numerator, x + (width - nw) / 2, y, size * 0.82, color)
    line_y = y + nh + gap

    page =
      Page.line(page,
        x1: x,
        y1: line_y,
        x2: x + width,
        y2: line_y,
        color: color,
        width: size * 0.035,
        origin: :top_left
      )

    {page, _} =
      draw(
        page,
        denominator,
        x + (width - dw) / 2,
        line_y + gap,
        size * 0.82,
        color
      )

    {page, width}
  end

  defp draw(page, {:root, value, index} = ast, x, y, size, color) do
    {width, _height} = do_measure(ast, size)
    index_width = if(index, do: elem(do_measure(index, size * 0.55), 0), else: 0)
    top_clearance = root_top_clearance(value, size)
    root_x = x + index_width
    value_x = root_x + size * 0.75
    {value_width, value_height} = do_measure(value, size)

    {page, _} =
      if(index,
        do: draw(page, index, x, y + top_clearance * 0.35, size * 0.55, color),
        else: {page, 0}
      )

    radical_bottom = y + top_clearance + value_height

    page =
      page
      |> Page.line(
        x1: root_x,
        y1: y + top_clearance + value_height * 0.55,
        x2: root_x + size * 0.22,
        y2: radical_bottom,
        color: color,
        width: size * 0.035,
        origin: :top_left
      )
      |> Page.line(
        x1: root_x + size * 0.22,
        y1: radical_bottom,
        x2: root_x + size * 0.5,
        y2: y + size * 0.1,
        color: color,
        width: size * 0.035,
        origin: :top_left
      )
      |> Page.line(
        x1: root_x + size * 0.5,
        y1: y + size * 0.1,
        x2: value_x + value_width,
        y2: y + size * 0.1,
        color: color,
        width: size * 0.035,
        origin: :top_left
      )

    {page, _} = draw(page, value, value_x, y + top_clearance + size * 0.25, size, color)
    {page, width}
  end

  defp draw(page, {:matrix, rows} = ast, x, y, size, color) do
    {width, height} = do_measure(ast, size)
    columns = rows |> Enum.map(&length/1) |> Enum.max(fn -> 1 end)
    cell_width = (width - size * 0.8) / max(columns, 1)
    row_heights = matrix_row_heights(rows, size)

    page =
      page
      |> Page.line(
        x1: x + size * 0.3,
        y1: y,
        x2: x,
        y2: y,
        color: color,
        width: size * 0.035,
        origin: :top_left
      )
      |> Page.line(
        x1: x,
        y1: y,
        x2: x,
        y2: y + height,
        color: color,
        width: size * 0.035,
        origin: :top_left
      )
      |> Page.line(
        x1: x,
        y1: y + height,
        x2: x + size * 0.3,
        y2: y + height,
        color: color,
        width: size * 0.035,
        origin: :top_left
      )
      |> Page.line(
        x1: x + width - size * 0.3,
        y1: y,
        x2: x + width,
        y2: y,
        color: color,
        width: size * 0.035,
        origin: :top_left
      )
      |> Page.line(
        x1: x + width,
        y1: y,
        x2: x + width,
        y2: y + height,
        color: color,
        width: size * 0.035,
        origin: :top_left
      )
      |> Page.line(
        x1: x + width,
        y1: y + height,
        x2: x + width - size * 0.3,
        y2: y + height,
        color: color,
        width: size * 0.035,
        origin: :top_left
      )

    {page, _offset} =
      rows
      |> Enum.zip(row_heights)
      |> Enum.reduce({page, 0}, fn {row, row_height}, {current, offset} ->
        current =
          row
          |> Enum.with_index()
          |> Enum.reduce(current, fn {cell, column_index}, cell_page ->
            {actual_width, cell_height} = do_measure(cell, size * 0.8)
            cell_x = x + size * 0.4 + column_index * cell_width + (cell_width - actual_width) / 2
            cell_y = y + size * 0.175 + offset + (row_height - cell_height) / 2
            {cell_page, _} = draw(cell_page, cell, cell_x, cell_y, size * 0.8, color)
            cell_page
          end)

        {current, offset + row_height}
      end)

    {page, width}
  end

  defp draw(page, {kind, base, script} = ast, x, y, size, color)
       when kind in [:superscript, :subscript] do
    {_width, _height} = do_measure(ast, size)
    base_y = if(kind == :superscript, do: y + size * 0.25, else: y)
    {page, base_width} = draw(page, base, x, base_y, size, color)
    script_y = if(kind == :superscript, do: y, else: y + size * 0.55)
    gap = script_gap(size)
    {page, script_width} = draw(page, script, x + base_width + gap, script_y, size * 0.6, color)
    {page, base_width + gap + script_width}
  end

  defp draw(page, {:integral, lower, upper, body, variable} = ast, x, y, size, color) do
    {width, _height} = do_measure(ast, size)

    limit_width =
      Enum.max([
        0
        | Enum.map(Enum.reject([lower, upper], &is_nil/1), &elem(do_measure(&1, size * 0.55), 0))
      ])

    integral_x = x

    page =
      Page.path(
        page,
        [
          {:move_to, integral_x + size * 0.8, y + size * 0.06},
          {:curve_to, integral_x + size * 0.4, y, integral_x + size * 0.45, y + size * 0.45,
           integral_x + size * 0.4, y + size * 0.78},
          {:curve_to, integral_x + size * 0.3, y + size * 1.2, integral_x + size * 0.4,
           y + size * 1.92, integral_x, y + size * 2.02}
        ],
        stroke: true,
        fill: false,
        stroke_color: color,
        line_width: size * 0.065,
        origin: :top_left
      )

    limit_x = integral_x + size * 1.05

    {page, _} =
      if(upper,
        do: draw(page, upper, limit_x, y, size * 0.55, color),
        else: {page, 0}
      )

    {page, _} =
      if(lower,
        do: draw(page, lower, limit_x, y + size * 1.78, size * 0.55, color),
        else: {page, 0}
      )

    body_x = integral_x + max(size * 1.55, size * 1.3 + limit_width)
    {page, body_width} = draw(page, body, body_x, y + size * 0.55, size, color)

    {page, _} =
      draw(
        page,
        {:symbol, " d#{variable}"},
        body_x + body_width + size * 0.12,
        y + size * 0.55,
        size,
        color
      )

    {page, width}
  end

  defp matrix_row_heights([], size), do: [size]

  defp matrix_row_heights(rows, size) do
    Enum.map(rows, fn row ->
      row
      |> Enum.map(&(elem(do_measure(&1, size * 0.8), 1) + size * 0.25))
      |> Enum.max(fn -> size end)
    end)
  end

  defp axis({:fraction, numerator, _}, size),
    do: elem(do_measure(numerator, size * 0.82), 1) + size * 0.16

  defp axis({:row, items}, size),
    do: items |> Enum.map(&axis(&1, size)) |> Enum.max(fn -> size * 0.68 end)

  defp axis({:superscript, base, _}, size), do: axis(base, size) + size * 0.25
  defp axis({:subscript, base, _}, size), do: axis(base, size)
  defp axis({:matrix, _} = ast, size), do: elem(do_measure(ast, size), 1) / 2

  defp axis({:root, value, _}, size),
    do: root_top_clearance(value, size) + size * 0.25 + axis(value, size)

  defp axis({:integral, _, _, body, _}, size), do: size * 0.55 + axis(body, size)
  defp axis(_, size), do: size * 0.68

  defp script_gap(size), do: size * 0.07

  defp root_top_clearance({:superscript, _base, _script}, size), do: size * 0.16

  defp root_top_clearance({:row, items}, size),
    do: Enum.map(items, &root_top_clearance(&1, size)) |> Enum.max(fn -> 0 end)

  defp root_top_clearance({:fraction, numerator, denominator}, size),
    do:
      max(
        root_top_clearance(numerator, size * 0.82),
        root_top_clearance(denominator, size * 0.82)
      )

  defp root_top_clearance({:root, value, _index}, size),
    do: root_top_clearance(value, size) * 0.5

  defp root_top_clearance(_ast, _size), do: 0
end
