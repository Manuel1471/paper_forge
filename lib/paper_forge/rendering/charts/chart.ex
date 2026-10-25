defmodule PaperForge.Chart do
  @moduledoc """
  Native vector charts for top-left pages. Used by `PaperForge.Flow.chart/3`.

  Supports categorical bars, lines, areas and scatter plots, plus pies and donuts.
  Signed Cartesian data uses a shared linear scale including zero. Labels are
  shortened or sampled to fit; data points are never silently dropped.
  """
  alias PaperForge.{Color, Page, TextMetrics, TextWrapper}

  @types [:bar, :line, :area, :scatter, :pie, :donut]
  @palette [0x00887A, 0x176B87, 0xE8AD35, 0xE76554, 0x6653A5, 0x4A9BC3]

  def render(page, series, options) do
    validate!(page, series, options)
    box = box(options)
    page = background(page, box, options)
    {page, box} = titles(page, box, options)
    type = Keyword.get(options, :chart_type, :bar)

    cond do
      series == [] -> empty(page, box, "No data", options)
      type in [:pie, :donut] -> radial(page, series, box, type, options)
      true -> cartesian(page, series, box, type, options)
    end
  end

  defp validate!(page, series, options) do
    unless page.origin == :top_left, do: raise(ArgumentError, "charts require a top-left page")

    unless Keyword.get(options, :chart_type, :bar) in @types,
      do: raise(ArgumentError, "unsupported chart type")

    unless is_list(series) and Enum.all?(series, &valid_pair?/1),
      do: raise(ArgumentError, "chart data must be {label, numeric_value} pairs")

    validate_dimensions!(options)
    integer_range!(Keyword.get(options, :tick_count, 5), 2..10, :tick_count)
    integer_range!(Keyword.get(options, :value_decimals, 1), 0..6, :value_decimals)
    validate_ratio!(Keyword.get(options, :inner_radius, 0.55))
  end

  defp valid_pair?({label, value}),
    do: (is_binary(label) or is_number(label)) and is_number(value)

  defp valid_pair?(_), do: false

  defp validate_dimensions!(options) do
    for key <- [:width, :height], do: positive!(Keyword.fetch!(options, key), key)

    for {key, default} <- [chart_padding: 12, gap: 12, point_radius: 3, line_width: 2],
        do: nonnegative!(Keyword.get(options, key, default), key)

    for {key, default} <- [label_size: 8, value_size: 8, title_size: 14],
        do: positive!(Keyword.get(options, key, default), key)
  end

  defp positive!(value, _) when is_number(value) and value > 0, do: :ok
  defp positive!(_, key), do: raise(ArgumentError, "chart #{key} must be positive")
  defp nonnegative!(value, _) when is_number(value) and value >= 0, do: :ok
  defp nonnegative!(_, key), do: raise(ArgumentError, "chart #{key} must be non-negative")

  defp integer_range!(value, range, key) do
    unless is_integer(value) and value in range,
      do: raise(ArgumentError, "#{key} must be between #{range.first} and #{range.last}")
  end

  defp validate_ratio!(ratio) when is_number(ratio) and ratio > 0 and ratio < 1, do: :ok
  defp validate_ratio!(_), do: raise(ArgumentError, "inner_radius must be between 0 and 1")

  defp box(options) do
    padding = Keyword.get(options, :chart_padding, 12)

    box = %{
      x: Keyword.get(options, :x, 0) + padding,
      y: Keyword.get(options, :y, 0) + padding,
      w: Keyword.fetch!(options, :width) - 2 * padding,
      h: Keyword.fetch!(options, :height) - 2 * padding
    }

    ensure_space!(box)
    box
  end

  defp ensure_space!(%{w: w, h: h}) do
    if w < 16 or h < 16,
      do: raise(ArgumentError, "chart is too small for its padding, title and labels")
  end

  defp background(page, _box, options) do
    case Keyword.get(options, :background_color) do
      nil ->
        page

      color ->
        Page.rectangle(page,
          x: Keyword.get(options, :x, 0),
          y: Keyword.get(options, :y, 0),
          width: options[:width],
          height: options[:height],
          fill: true,
          stroke: false,
          fill_color: color
        )
    end
  end

  defp titles(page, box, options) do
    Enum.reduce([:title, :subtitle], {page, box}, fn key, {current, area} ->
      render_title(current, area, key, Keyword.get(options, key), options)
    end)
  end

  defp render_title(page, box, _, nil, _), do: {page, box}

  defp render_title(page, box, key, text, options) do
    size =
      if key == :title,
        do: Keyword.get(options, :title_size, 14),
        else: Keyword.get(options, :label_size, 8)

    lines = TextWrapper.wrap(to_string(text), width: box.w, size: size, font: :helvetica)
    height = length(lines) * size * 1.3 + 8
    next = %{box | y: box.y + height, h: box.h - height}
    ensure_space!(next)

    {Page.text_box(page, Enum.join(lines, "\n"),
       x: box.x,
       y: box.y + size,
       width: box.w,
       size: size,
       line_height: size * 1.3,
       font: :helvetica,
       color: label_color(options)
     ), next}
  end

  defp cartesian(page, series, box, type, options) do
    {low, high, ticks} = scale(series, options)
    interval = Enum.at(ticks, 1, high) - hd(ticks)
    decimals = min(max(ceil(-:math.log10(interval)) + 1, 1), 6)
    options = Keyword.put_new(options, :value_decimals, decimals)
    size = Keyword.get(options, :label_size, 8)
    axis? = Keyword.get(options, :show_axes, true)

    axis_width =
      if axis?, do: Enum.max(Enum.map(ticks, &text_width(number(&1, options), size))) + 9, else: 0

    value_space =
      if Keyword.get(options, :show_values, true),
        do: Keyword.get(options, :value_size, 8) + 7,
        else: 4

    plot = %{
      x: box.x + axis_width,
      y: box.y + value_space,
      w: box.w - axis_width,
      h: box.h - size * 1.8 - 4 - value_space - if(low < 0, do: value_space, else: 0),
      label_y: box.y + box.h - 2
    }

    ensure_space!(plot)
    project = fn value -> plot.y + plot.h * (high - value) / (high - low) end
    page = axes(page, plot, ticks, project, options)
    count = length(series)
    slot = plot.w / count
    gap = min(Keyword.get(options, :gap, 12), slot * 0.4)
    bar_width = slot - gap
    colors = colors(options)

    points =
      series
      |> Enum.with_index()
      |> Enum.map(fn {{label, value}, index} ->
        %{
          x: plot.x + slot * (index + 0.5),
          y: project.(value),
          label: to_string(label),
          value: value,
          index: index
        }
      end)

    page = draw_data(page, points, type, project.(0), bar_width, colors, options)
    labels(page, points, plot, slot, options)
  end

  defp scale(series, options) do
    values = Enum.map(series, &elem(&1, 1))
    minimum = min(Enum.min(values), 0)
    maximum = max(Enum.max(values), 0)
    span = if minimum == maximum, do: 1, else: maximum - minimum
    step = nice_step(span / (Keyword.get(options, :tick_count, 5) - 1))
    low = Keyword.get(options, :y_min, Float.floor(minimum / step) * step)

    high =
      Keyword.get(
        options,
        :y_max,
        Float.ceil(if(minimum == maximum, do: maximum + 1, else: maximum) / step) * step
      )

    unless is_number(low) and is_number(high) and low < high and low <= minimum and
             high >= maximum do
      raise ArgumentError,
            "y_min/y_max must contain zero and every data value, with y_min < y_max"
    end

    step = nice_step((high - low) / (Keyword.get(options, :tick_count, 5) - 1))
    first = ceil(low / step)
    last = floor(high / step)
    ticks = for i <- first..last, do: i * step
    {low, high, ticks}
  end

  defp nice_step(raw) do
    power = :math.pow(10, Float.floor(:math.log10(raw)))
    fraction = raw / power
    multiplier = Enum.find([1, 2, 2.5, 5, 10], &(&1 >= fraction))
    multiplier * power
  end

  defp axes(page, plot, ticks, project, options) do
    size = Keyword.get(options, :label_size, 8)

    page =
      Enum.reduce(ticks, page, fn value, current ->
        y = project.(value)

        current =
          if Keyword.get(options, :show_grid, true),
            do:
              Page.line(current,
                x1: plot.x,
                y1: y,
                x2: plot.x + plot.w,
                y2: y,
                color: Keyword.get(options, :grid_color, Color.gray(0.88)),
                width: 0.5
              ),
            else: current

        if Keyword.get(options, :show_axes, true),
          do:
            Page.text(current, number(value, options),
              x: Keyword.get(options, :x, 0) + Keyword.get(options, :chart_padding, 12),
              y: y + size * 0.35,
              width:
                plot.x - Keyword.get(options, :x, 0) - Keyword.get(options, :chart_padding, 12) -
                  7,
              align: :right,
              size: size,
              font: :helvetica,
              color: label_color(options)
            ),
          else: current
      end)

    if Keyword.get(options, :show_axes, true),
      do:
        Page.line(page,
          x1: plot.x,
          y1: project.(0),
          x2: plot.x + plot.w,
          y2: project.(0),
          font: :helvetica,
          color: label_color(options),
          width: 0.8
        ),
      else: page
  end

  defp draw_data(page, points, :bar, zero, width, colors, _options) do
    Enum.reduce(points, page, fn p, current ->
      if p.value == 0 do
        current
      else
        Page.rectangle(current,
          x: p.x - width / 2,
          y: min(zero, p.y),
          width: width,
          height: abs(zero - p.y),
          fill: true,
          stroke: false,
          fill_color: Enum.at(colors, rem(p.index, length(colors)))
        )
      end
    end)
  end

  defp draw_data(page, points, type, zero, width, colors, options) do
    color = hd(colors)

    path =
      points
      |> Enum.with_index()
      |> Enum.map(fn {p, i} ->
        if i == 0, do: {:move_to, p.x, p.y}, else: {:line_to, p.x, p.y}
      end)

    page =
      if type == :area and length(points) > 1 do
        area =
          path ++ [{:line_to, List.last(points).x, zero}, {:line_to, hd(points).x, zero}, :close]

        Page.path(page, area,
          fill: true,
          stroke: false,
          fill_color: Keyword.get(options, :fill_color, Color.gray(0.9))
        )
      else
        page
      end

    page =
      if type in [:line, :area] and length(points) > 1,
        do:
          Page.path(page, path,
            fill: false,
            stroke: true,
            stroke_color: color,
            line_width: Keyword.get(options, :line_width, 2)
          ),
        else: page

    radius = min(Keyword.get(options, :point_radius, 3), width / 3)

    if radius > 0 do
      Enum.reduce(points, page, fn p, current ->
        Page.circle(current,
          x: p.x,
          y: p.y,
          radius: radius,
          fill: true,
          stroke: false,
          fill_color: color
        )
      end)
    else
      page
    end
  end

  defp labels(page, points, plot, slot, options) do
    size = Keyword.get(options, :label_size, 8)
    value_size = Keyword.get(options, :value_size, 8)
    label_width = points |> Enum.map(&text_width(&1.label, size)) |> Enum.max()
    label_step = max(ceil((min(label_width, 100) + 10) / slot), 1)

    value_width =
      points |> Enum.map(&text_width(number(&1.value, options), value_size)) |> Enum.max()

    value_step = max(ceil((value_width + 6) / slot), 1)

    Enum.reduce(points, page, fn p, current ->
      current
      |> category_label(p, plot, slot, label_step, size, options)
      |> value_label(p, plot, slot, value_step, value_width, value_size, options)
    end)
  end

  defp category_label(page, p, plot, slot, step, size, options) do
    if rem(p.index, step) == 0 do
      width = min(slot * step - 4, plot.x + plot.w - (p.x - slot / 2))

      Page.text(page, shorten(p.label, width, size),
        x: p.x - slot / 2,
        y: plot.label_y,
        width: width,
        align: if(step == 1, do: :center, else: :left),
        size: size,
        font: :helvetica,
        color: label_color(options)
      )
    else
      page
    end
  end

  defp value_label(page, p, plot, slot, step, value_width, size, options) do
    if Keyword.get(options, :show_values, true) and rem(p.index, step) == 0 do
      width = min(max(value_width, slot), plot.w)
      x = max(plot.x, min(p.x - width / 2, plot.x + plot.w - width))
      y = if p.value < 0, do: p.y + size + 4, else: p.y - 5

      Page.text(page, shorten(number(p.value, options), width, size),
        x: x,
        y: y,
        width: width,
        align: :center,
        size: size,
        font: :helvetica,
        color: label_color(options)
      )
    else
      page
    end
  end

  defp radial(page, series, box, type, options) do
    if Enum.any?(series, &(elem(&1, 1) < 0)),
      do: raise(ArgumentError, "pie and donut values must be non-negative")

    total = Enum.sum(Enum.map(series, &elem(&1, 1)))

    if total == 0 do
      empty(page, box, "No positive values", options)
    else
      radial_data(page, series, box, type, total, options)
    end
  end

  defp radial_data(page, series, box, type, total, options) do
    legend? = Keyword.get(options, :show_legend, true)
    diameter = min(box.h, if(legend?, do: box.w * 0.46, else: box.w))
    radius = diameter / 2
    cx = if legend?, do: box.x + radius, else: box.x + box.w / 2
    cy = box.y + box.h / 2
    palette = colors(options)

    {page, _} =
      series
      |> Enum.with_index()
      |> Enum.reduce({page, -90}, fn {{_, value}, i}, {current, angle} ->
        sweep = value / total * 360

        {wedge(current, cx, cy, radius, angle, sweep, Enum.at(palette, rem(i, length(palette)))),
         angle + sweep}
      end)

    page =
      if type == :donut,
        do:
          Page.circle(page,
            x: cx,
            y: cy,
            radius: radius * Keyword.get(options, :inner_radius, 0.55),
            fill: true,
            stroke: false,
            fill_color: Keyword.get(options, :background_color, Color.white())
          ),
        else: page

    if legend?,
      do:
        legend(
          page,
          series,
          %{box | x: cx + radius + 16, w: box.w - diameter - 16},
          total,
          options
        ),
      else: page
  end

  defp legend(page, series, box, total, options) do
    size = Keyword.get(options, :label_size, 8)
    width = box.w - 14

    if width < 16,
      do:
        raise(
          ArgumentError,
          "chart is too narrow for its legend; increase width or disable show_legend"
        )

    rows =
      Enum.map(series, fn {label, value} ->
        text =
          if Keyword.get(options, :show_values, true),
            do: "#{label}  #{number(value, options)} (#{Float.round(value / total * 100, 1)}%)",
            else: to_string(label)

        TextWrapper.wrap(text, width: width, size: size, font: :helvetica)
      end)

    required = Enum.sum(Enum.map(rows, &(length(&1) * size * 1.3 + 8)))

    if required > box.h,
      do:
        raise(ArgumentError, "chart legend does not fit; increase height or disable show_legend")

    palette = colors(options)

    {page, _} =
      rows
      |> Enum.with_index()
      |> Enum.reduce({page, box.y + (box.h - required) / 2}, fn {lines, i}, {current, y} ->
        current =
          current
          |> Page.rectangle(
            x: box.x,
            y: y + 1,
            width: 7,
            height: 7,
            fill: true,
            stroke: false,
            fill_color: Enum.at(palette, rem(i, length(palette)))
          )
          |> Page.text_box(Enum.join(lines, "\n"),
            x: box.x + 14,
            y: y + size,
            width: width,
            size: size,
            line_height: size * 1.3,
            font: :helvetica,
            color: label_color(options)
          )

        {current, y + length(lines) * size * 1.3 + 8}
      end)

    page
  end

  defp wedge(page, _, _, _, _, sweep, _) when sweep <= 0, do: page

  defp wedge(page, cx, cy, radius, _, sweep, color) when sweep >= 359.999999 do
    Page.circle(page, x: cx, y: cy, radius: radius, fill: true, stroke: false, fill_color: color)
  end

  defp wedge(page, cx, cy, radius, start, sweep, color) do
    steps = ceil(sweep / 90)
    delta = sweep / steps * :math.pi() / 180
    angle = start * :math.pi() / 180
    first = {:line_to, cx + radius * :math.cos(angle), cy + radius * :math.sin(angle)}

    curves =
      Enum.map(0..(steps - 1), fn i ->
        a = angle + i * delta
        b = a + delta
        k = 4 / 3 * :math.tan(delta / 4)

        {:curve_to, cx + radius * (:math.cos(a) - k * :math.sin(a)),
         cy + radius * (:math.sin(a) + k * :math.cos(a)),
         cx + radius * (:math.cos(b) + k * :math.sin(b)),
         cy + radius * (:math.sin(b) - k * :math.cos(b)), cx + radius * :math.cos(b),
         cy + radius * :math.sin(b)}
      end)

    Page.path(page, [{:move_to, cx, cy}, first] ++ curves ++ [:close],
      fill: true,
      stroke: false,
      fill_color: color
    )
  end

  defp empty(page, box, text, options),
    do:
      Page.text(page, text,
        x: box.x,
        y: box.y + box.h / 2 + 4,
        width: box.w,
        align: :center,
        size: Keyword.get(options, :label_size, 8),
        font: :helvetica,
        color: label_color(options)
      )

  defp shorten(text, width, size) do
    if text_width(text, size) <= width do
      text
    else
      text
      |> String.graphemes()
      |> Enum.reduce_while("", &fit_grapheme(&1, &2, width, size))
      |> then(&if(&1 == "", do: "", else: &1 <> "…"))
    end
  end

  defp fit_grapheme(glyph, acc, width, size) do
    if text_width(acc <> glyph <> "…", size) <= width,
      do: {:cont, acc <> glyph},
      else: {:halt, acc}
  end

  defp text_width(text, size), do: TextMetrics.line_width(text, font: :helvetica, size: size)

  defp number(value, options) do
    decimals = Keyword.get(options, :value_decimals, 1)
    rounded = Float.round(value * 1.0, decimals)

    text =
      if rounded == trunc(rounded),
        do: Integer.to_string(trunc(rounded)),
        else: Float.to_string(rounded)

    "#{Keyword.get(options, :value_prefix, "")}#{text}#{Keyword.get(options, :value_suffix, "")}"
  end

  defp label_color(options), do: Keyword.get(options, :label_color, Color.gray(0.3))

  defp colors(options) do
    case Keyword.get(options, :colors) do
      [_ | _] = colors -> colors
      _ -> default_colors(Keyword.get(options, :color))
    end
  end

  defp default_colors(nil), do: Enum.map(@palette, &hex_color/1)
  defp default_colors(color), do: [color]

  defp hex_color(hex),
    do:
      Color.rgb255(
        Bitwise.bsr(hex, 16),
        Bitwise.band(Bitwise.bsr(hex, 8), 255),
        Bitwise.band(hex, 255)
      )
end
