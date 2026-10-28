defmodule PaperForge.Layout.Visual do
  @moduledoc false
  alias PaperForge.{Color, Document, FontRegistry, Page, TextMetrics}
  alias PaperForge.Layout.{Block, Engine}

  @kinds [
    :box,
    :row,
    :column,
    :block_grid,
    :overlay,
    :shape,
    :icon,
    :badge,
    :button,
    :framed_image
  ]
  def kinds, do: @kinds

  def measure(%Block{content: kind} = block, available, document) when kind in @kinds do
    opts = defaults(kind, block.options)
    padding = nonnegative!(Keyword.get(opts, :padding, 0), :padding)
    gap = nonnegative!(Keyword.get(opts, :gap, 12), :gap)
    width = width!(kind, opts, block.children, available, document)
    inner = width - 2 * padding
    if inner <= 0, do: raise(ArgumentError, "visual padding consumes the available width")
    validate_style!(opts)
    children = inherit(block.children, opts)
    {items, natural} = contents(kind, children, inner, gap, opts, document)
    height = Keyword.get(opts, :height, natural + 2 * padding)
    positive!(height, :height)

    if height + 0.001 < natural + 2 * padding,
      do: raise(ArgumentError, "visual height is smaller than its content")

    %{kind: kind, width: width, height: height, padding: padding, items: items, options: opts}
  end

  defp defaults(kind, opts) when kind in [:badge, :button] do
    Keyword.merge(
      [
        padding: 8,
        border_radius: 8,
        size: 10,
        background_color: Color.rgb(0.91, 0.95, 0.96),
        color: Color.rgb(0.08, 0.24, 0.28)
      ],
      opts
    )
  end

  defp defaults(:box, opts), do: Keyword.put_new(opts, :padding, 14)
  defp defaults(_, opts), do: opts

  defp width!(kind, opts, children, available, document) do
    default =
      case kind do
        :icon ->
          Keyword.get(opts, :size, 24)

        :shape ->
          available

        kind when kind in [:badge, :button] ->
          text = children |> Enum.map_join("", &to_string(&1.content))

          text_width =
            TextMetrics.width(text,
              font: metric_font(document, opts, text),
              size: Keyword.get(opts, :size, 10)
            )

          min(available, text_width + 2 * Keyword.get(opts, :padding, 8) + 2 + icon_width(opts))

        _ ->
          available
      end

    width =
      case Keyword.get(opts, :width, default) do
        :content -> available
        value -> positive!(value, :width)
      end

    if width > available + 0.001, do: raise(ArgumentError, "visual width exceeds available width")
    width
  end

  defp metric_font(document, opts, text) do
    key = Document.resolve_text_font_key(document, opts, text)

    case FontRegistry.fetch(document.font_registry, key) do
      {:ok, font} -> font
      :error -> key
    end
  end

  defp contents(kind, children, width, gap, opts, doc)
       when kind in [:box, :column, :badge, :button] do
    if kind in [:badge, :button] and Keyword.has_key?(opts, :icon) do
      inline_icon(children, width, opts, doc)
    else
      children = Enum.intersperse(children, Block.new(:spacer, gap))
      {placements, height} = Engine.measure_fragment(children, width, doc)
      {[%{x: 0, y: 0, width: width, height: height, placements: placements}], height}
    end
  end

  defp contents(kind, children, width, gap, opts, doc) when kind in [:row, :block_grid] do
    count = if kind == :row, do: max(length(children), 1), else: Keyword.get(opts, :columns, 2)

    unless is_integer(count) and count > 0 and count <= 64,
      do: raise(ArgumentError, "columns must be an integer from 1 to 64")

    widths =
      Keyword.get(
        opts,
        :column_widths,
        List.duplicate((width - gap * (count - 1)) / count, count)
      )

    unless is_list(widths) and length(widths) == count,
      do: raise(ArgumentError, "column_widths must match the column count")

    Enum.each(widths, &positive!(&1, :column_width))

    if Enum.sum(widths) + gap * (count - 1) > width + 0.001,
      do: raise(ArgumentError, "columns and gaps exceed available width")

    {rows, height} =
      children
      |> Enum.chunk_every(count)
      |> Enum.map_reduce(0, fn row, y ->
        {cells, _x} =
          Enum.zip(row, widths)
          |> Enum.map_reduce(0, fn {child, w}, x ->
            {placements, h} = Engine.measure_fragment([child], w, doc)
            {%{x: x, y: y, width: w, height: h, placements: placements}, x + w + gap}
          end)

        row_height = cells |> Enum.map(& &1.height) |> Enum.max(fn -> 0 end)

        cells =
          Enum.map(cells, fn cell ->
            %{cell | y: y + valign(Keyword.get(opts, :valign, :top), row_height - cell.height)}
          end)

        {cells, y + row_height + gap}
      end)

    {List.flatten(rows), max(height - gap, 0)}
  end

  defp contents(:overlay, children, width, _gap, _opts, doc) do
    items =
      Enum.map(children, fn child ->
        x = nonnegative!(Keyword.get(child.options, :offset_x, 0), :offset_x)
        y = nonnegative!(Keyword.get(child.options, :offset_y, 0), :offset_y)
        if x >= width, do: raise(ArgumentError, "overlay offset exceeds width")
        {placements, h} = Engine.measure_fragment([child], width - x, doc)
        %{x: x, y: y, width: width - x, height: h, placements: placements}
      end)

    {items, items |> Enum.map(&(&1.y + &1.height)) |> Enum.max(fn -> 0 end)}
  end

  defp contents(kind, children, width, _gap, opts, _doc)
       when kind in [:shape, :icon, :framed_image] do
    height = Keyword.get(opts, :height, if(kind == :icon, do: width, else: 100))
    positive!(height, :height)
    caption = Keyword.get(opts, :caption)
    # Captions are ordinary measured children appended by the declarative compiler.
    if caption && kind == :framed_image,
      do: raise(ArgumentError, "use a column with a caption paragraph around framed_image")

    {children, height}
  end

  defp icon_width(opts) do
    if Keyword.has_key?(opts, :icon),
      do:
        positive!(Keyword.get(opts, :icon_size, 14), :icon_size) +
          nonnegative!(Keyword.get(opts, :icon_gap, 6), :icon_gap),
      else: 0
  end

  defp inline_icon(children, width, opts, doc) do
    size = positive!(Keyword.get(opts, :icon_size, 14), :icon_size)
    occupied = icon_width(opts)
    if width <= occupied, do: raise(ArgumentError, "button is too narrow for its icon")

    icon =
      Block.new(:visual, :icon,
        source: Keyword.fetch!(opts, :icon),
        width: size,
        height: size,
        color: Keyword.get(opts, :color, Color.black()),
        space_after: 0
      )

    {icon_placements, icon_height} = Engine.measure_fragment([icon], size, doc)
    {text_placements, text_height} = Engine.measure_fragment(children, width - occupied, doc)
    height = max(icon_height, text_height)

    {[
       %{
         x: 0,
         y: (height - icon_height) / 2,
         width: size,
         height: icon_height,
         placements: icon_placements
       },
       %{
         x: occupied,
         y: (height - text_height) / 2,
         width: width - occupied,
         height: text_height,
         placements: text_placements
       }
     ], height}
  end

  defp inherit(children, opts) do
    defaults = Keyword.take(opts, [:font, :size, :color, :line_height])
    Enum.map(children, fn block -> %{block | options: Keyword.merge(defaults, block.options)} end)
  end

  def render(page, plan, x, y, document) do
    opts = plan.options

    page =
      if plan.kind in [:shape, :framed_image],
        do: page,
        else: decoration(page, x, y, plan.width, plan.height, opts)

    page =
      case plan.kind do
        :shape ->
          shape(page, x, y, plan.width, plan.height, opts)

        :icon ->
          icon(page, x, y, plan.width, plan.height, opts)

        :framed_image ->
          framed_image(page, plan, x, y)

        _ ->
          Enum.reduce(plan.items, page, fn item, current ->
            Engine.render_fragment(
              current,
              item.placements,
              x + plan.padding + item.x,
              y + plan.padding + item.y,
              item.width,
              document
            )
          end)
      end

    case Keyword.get(opts, :link) do
      nil -> page
      uri -> Page.link(page, uri, x: x, y: y, width: plan.width, height: plan.height)
    end
  end

  defp framed_image(page, plan, x, y) do
    opts = plan.options

    radius =
      if Keyword.get(opts, :shape) == :circle,
        do: min(plan.width, plan.height) / 2,
        else: Keyword.get(opts, :border_radius, 0)

    if Keyword.get(opts, :shape) == :circle and plan.width != plan.height,
      do: raise(ArgumentError, "circular image requires equal width and height")

    path = rounded_path(x, y, plan.width, plan.height, radius)
    source = Keyword.fetch!(opts, :source)

    page =
      Page.clip(page, path, fn clipped ->
        Page.image(clipped, source,
          x: x,
          y: y,
          width: plan.width,
          height: plan.height,
          fit: Keyword.get(opts, :fit, :cover),
          focal_point: Keyword.get(opts, :focal_point, {0.5, 0.5})
        )
      end)

    decoration(
      page,
      x,
      y,
      plan.width,
      plan.height,
      opts |> Keyword.delete(:background_color) |> Keyword.put(:border_radius, radius)
    )
  end

  defp decoration(page, x, y, width, height, opts) do
    color = Keyword.get(opts, :background_color)
    border = Keyword.get(opts, :border_width, 0)

    if color || border > 0 do
      Page.path(page, rounded_path(x, y, width, height, Keyword.get(opts, :border_radius, 0)),
        fill: not is_nil(color),
        fill_color: color || Color.white(),
        stroke: border > 0,
        stroke_color: Keyword.get(opts, :border_color, Color.gray(0.8)),
        line_width: border
      )
    else
      page
    end
  end

  defp shape(page, x, y, w, h, opts) do
    kind = Keyword.get(opts, :shape, :rectangle)

    path =
      case kind do
        :rectangle ->
          rounded_path(x, y, w, h, Keyword.get(opts, :border_radius, 0))

        :circle ->
          diameter = min(w, h)
          ellipse_path(x + (w - diameter) / 2, y + (h - diameter) / 2, diameter, diameter)

        :ellipse ->
          ellipse_path(x, y, w, h)

        :line ->
          [{:move_to, x, y + h / 2}, {:line_to, x + w, y + h / 2}]

        :polygon ->
          polygon_path(Keyword.get(opts, :points, []), x, y, w, h)

        _ ->
          raise ArgumentError, "unsupported shape"
      end

    Page.path(page, path,
      fill: kind != :line,
      fill_color: Keyword.get(opts, :color, Color.rgb(0.05, 0.45, 0.48)),
      stroke: kind == :line or Keyword.get(opts, :border_width, 0) > 0,
      stroke_color: Keyword.get(opts, :border_color, Keyword.get(opts, :color, Color.black())),
      line_width:
        if(kind == :line,
          do: Keyword.get(opts, :line_width, 1),
          else: Keyword.get(opts, :border_width, 0)
        )
    )
  end

  defp polygon_path(points, x, y, w, h) when length(points) >= 3 do
    mapped =
      Enum.map(points, fn
        [px, py]
        when is_number(px) and is_number(py) and px >= 0 and px <= 1 and py >= 0 and py <= 1 ->
          {x + px * w, y + py * h}

        _ ->
          raise ArgumentError, "polygon points must be normalized [x,y] pairs between 0 and 1"
      end)

    [{first_x, first_y} | rest] = mapped

    [{:move_to, first_x, first_y}] ++
      Enum.map(rest, fn {px, py} -> {:line_to, px, py} end) ++ [:close]
  end

  defp polygon_path(_, _, _, _, _),
    do: raise(ArgumentError, "polygon requires at least three points")

  defp icon(page, x, y, w, h, opts) do
    source = Keyword.fetch!(opts, :source)

    svg =
      if String.starts_with?(String.trim_leading(source), "<"),
        do: source,
        else: icon_svg(source, Keyword.get(opts, :color, Color.rgb(0.05, 0.45, 0.48)))

    PaperForge.SVG.render(page, svg, x: x, y: y, width: w, height: h)
  end

  defp icon_svg(name, color) do
    path =
      case name do
        "check" ->
          "M4 12 L9 17 L20 6"

        "arrow_right" ->
          "M4 12 L20 12 M13 5 L20 12 L13 19"

        "mail" ->
          "M3 5 L21 5 L21 19 L3 19 Z M3 5 L12 13 L21 5"

        "star" ->
          "M12 2 L15 9 L22 9 L17 14 L19 22 L12 18 L5 22 L7 14 L2 9 L9 9 Z"

        "user" ->
          "M7 7 C7 0 17 0 17 7 C17 14 7 14 7 7 M3 22 C3 10 21 10 21 22"

        _ ->
          raise ArgumentError,
                "unknown icon #{inspect(name)}; provide SVG content for custom icons"
      end

    # Color is already a validated core color, not an interpolated SVG attribute.
    [r, g, b] =
      case color do
        %Color{space: :rgb, components: values} -> values
        %Color{space: :gray, components: [value]} -> [value, value, value]
      end

    "<svg viewBox=\"0 0 24 24\"><path d=\"#{path}\" fill=\"none\" stroke=\"rgb(#{round(r * 255)},#{round(g * 255)},#{round(b * 255)})\" stroke-width=\"1.8\"/></svg>"
  end

  def rounded_path(x, y, w, h, radius) do
    r = min(max(radius, 0), min(w, h) / 2)
    k = r * 0.5522847498

    [
      {:move_to, x + r, y},
      {:line_to, x + w - r, y},
      {:curve_to, x + w - r + k, y, x + w, y + r - k, x + w, y + r},
      {:line_to, x + w, y + h - r},
      {:curve_to, x + w, y + h - r + k, x + w - r + k, y + h, x + w - r, y + h},
      {:line_to, x + r, y + h},
      {:curve_to, x + r - k, y + h, x, y + h - r + k, x, y + h - r},
      {:line_to, x, y + r},
      {:curve_to, x, y + r - k, x + r - k, y, x + r, y},
      :close
    ]
  end

  defp ellipse_path(x, y, w, h) do
    k = 0.5522847498
    rx = w / 2
    ry = h / 2
    cx = x + rx
    cy = y + ry

    [
      {:move_to, cx + rx, cy},
      {:curve_to, cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry},
      {:curve_to, cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy},
      {:curve_to, cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry},
      {:curve_to, cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy},
      :close
    ]
  end

  defp validate_style!(opts) do
    case Keyword.get(opts, :link) do
      nil ->
        :ok

      uri when is_binary(uri) and byte_size(uri) > 0 ->
        unless URI.parse(uri).scheme in ["https", "http", "mailto", "tel"],
          do: raise(ArgumentError, "unsupported visual link scheme")

      _ ->
        raise ArgumentError, "visual link must be a nonempty URI"
    end

    for key <- [:border_width, :border_radius, :space_after, :space_before],
        do: nonnegative!(Keyword.get(opts, key, 0), key)

    unless Keyword.get(opts, :align, :left) in [:left, :center, :right],
      do: raise(ArgumentError, "invalid visual alignment")

    unless Keyword.get(opts, :valign, :top) in [:top, :middle, :bottom],
      do: raise(ArgumentError, "invalid visual vertical alignment")
  end

  defp valign(:top, _), do: 0
  defp valign(:middle, delta), do: delta / 2
  defp valign(:bottom, delta), do: delta
  defp positive!(value, _) when is_number(value) and value > 0, do: value
  defp positive!(_, key), do: raise(ArgumentError, "#{key} must be positive")
  defp nonnegative!(value, _) when is_number(value) and value >= 0, do: value
  defp nonnegative!(_, key), do: raise(ArgumentError, "#{key} must be nonnegative")
end
