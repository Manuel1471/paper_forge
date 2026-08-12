defmodule PaperForge.SVG do
  @moduledoc """
  Renders SVG geometry as native PDF vectors.

  Supported elements include groups, paths, rectangles, lines, circles,
  ellipses, polygons, and polylines. Presentation attributes and inline styles
  cascade through groups. `viewBox`, affine transforms, and clip paths are
  applied before PDF operations are emitted.
  """

  alias PaperForge.Color
  alias PaperForge.Page

  @identity {1.0, 0.0, 0.0, 1.0, 0.0, 0.0}
  @kappa 0.552_284_749_8

  @spec render(Page.t(), binary(), keyword()) :: Page.t()
  def render(%Page{} = page, svg, options) when is_binary(svg) and is_list(options) do
    {root, _rest} = :xmerl_scan.string(String.to_charlist(svg), quiet: true)
    attrs = attributes(root)
    matrix = viewbox_matrix(attrs, options)
    clips = collect_clip_paths(root, matrix)

    root
    |> child_elements()
    |> Enum.reduce(page, fn node, current ->
      render_node(current, node, %{}, matrix, nil, clips)
    end)
  rescue
    error ->
      raise ArgumentError, "invalid SVG input: #{Exception.message(error)}"
  end

  defp render_node(page, node, inherited_style, inherited_matrix, inherited_clip, clips) do
    name = element_name(node)
    attrs = attributes(node)
    style = Map.merge(inherited_style, presentation(attrs))
    matrix = multiply(inherited_matrix, parse_transform(attrs["transform"]))
    clip = resolve_clip(attrs["clip-path"], inherited_clip, clips)

    case name do
      "g" ->
        Enum.reduce(child_elements(node), page, fn child, current ->
          render_node(current, child, style, matrix, clip, clips)
        end)

      "text" ->
        render_text(page, node, attrs, style, matrix)

      name when name in ["defs", "clipPath", "title", "desc"] ->
        page

      _ ->
        case element_path(name, attrs) do
          [] ->
            page

          segments ->
            Page.path(page, transform_path(segments, matrix), path_options(style, clip))
        end
    end
  end

  defp render_text(page, node, attrs, style, matrix) do
    text = node_text(node) |> String.trim()
    {x, y} = transform_point(number(attrs["x"], 0), number(attrs["y"], 0), matrix)
    size = number(Map.get(style, "font-size"), 12) * matrix_scale(matrix)
    estimated_width = String.length(text) * size * 0.55

    x =
      case Map.get(style, "text-anchor", attrs["text-anchor"]) do
        "middle" -> x - estimated_width / 2
        "end" -> x - estimated_width
        _ -> x
      end

    Page.text(page, text,
      x: x,
      y: y - size,
      size: size,
      color: color(Map.get(style, "fill", "black")),
      weight: svg_weight(Map.get(style, "font-weight")),
      style: svg_font_style(Map.get(style, "font-style")),
      origin: :top_left
    )
  end

  defp node_text({:xmlElement, _, _, _, _, _, _, _, content, _, _, _}) do
    content
    |> Enum.map(fn
      {:xmlText, _, _, _, value, _} -> to_string(value)
      child = {:xmlElement, _, _, _, _, _, _, _, _, _, _, _} -> node_text(child)
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp matrix_scale({a, b, c, d, _e, _f}),
    do: max((:math.sqrt(a * a + b * b) + :math.sqrt(c * c + d * d)) / 2, 0.01)

  defp collect_clip_paths(root, matrix) do
    root
    |> descendants()
    |> Enum.filter(&(element_name(&1) == "clipPath"))
    |> Map.new(fn node ->
      attrs = attributes(node)
      clip_matrix = multiply(matrix, parse_transform(attrs["transform"]))

      segments =
        node
        |> child_elements()
        |> Enum.flat_map(fn child ->
          child_attrs = attributes(child)
          child_matrix = multiply(clip_matrix, parse_transform(child_attrs["transform"]))
          transform_path(element_path(element_name(child), child_attrs), child_matrix)
        end)

      {attrs["id"], segments}
    end)
  end

  defp descendants(node) do
    children = child_elements(node)
    children ++ Enum.flat_map(children, &descendants/1)
  end

  defp resolve_clip(nil, inherited, _clips), do: inherited

  defp resolve_clip(value, inherited, clips) do
    case Regex.run(~r/url\(\s*#([^)]+)\s*\)/, value) do
      [_, id] -> Map.get(clips, id, inherited)
      _ -> inherited
    end
  end

  defp path_options(style, clip) do
    fill = Map.get(style, "fill", "black")
    stroke = Map.get(style, "stroke", "none")

    [
      fill: fill != "none",
      fill_color: color(fill),
      stroke: stroke != "none",
      stroke_color: color(stroke),
      line_width: number(Map.get(style, "stroke-width"), 1),
      fill_rule: if(Map.get(style, "fill-rule") == "evenodd", do: :evenodd, else: :nonzero),
      clip_path: clip,
      origin: :top_left
    ]
  end

  defp presentation(attrs) do
    inline =
      attrs
      |> Map.get("style", "")
      |> String.split(";", trim: true)
      |> Enum.flat_map(fn declaration ->
        case String.split(declaration, ":", parts: 2) do
          [key, value] -> [{String.trim(key), String.trim(value)}]
          _ -> []
        end
      end)
      |> Map.new()

    attrs
    |> Map.take([
      "fill",
      "stroke",
      "stroke-width",
      "fill-rule",
      "stroke-linecap",
      "stroke-linejoin",
      "opacity",
      "font-family",
      "font-size",
      "font-style",
      "font-weight",
      "text-anchor"
    ])
    |> Map.merge(inline)
  end

  defp element_path("path", attrs), do: parse_path(Map.get(attrs, "d", ""))

  defp element_path("rect", attrs) do
    x = number(attrs["x"], 0)
    y = number(attrs["y"], 0)
    width = number(attrs["width"], 0)
    height = number(attrs["height"], 0)

    [
      {:move_to, x, y},
      {:line_to, x + width, y},
      {:line_to, x + width, y + height},
      {:line_to, x, y + height},
      :close
    ]
  end

  defp element_path("line", attrs) do
    [
      {:move_to, number(attrs["x1"], 0), number(attrs["y1"], 0)},
      {:line_to, number(attrs["x2"], 0), number(attrs["y2"], 0)}
    ]
  end

  defp element_path("polygon", attrs), do: points_path(attrs["points"], true)
  defp element_path("polyline", attrs), do: points_path(attrs["points"], false)

  defp element_path("circle", attrs) do
    ellipse_path(
      number(attrs["cx"], 0),
      number(attrs["cy"], 0),
      number(attrs["r"], 0),
      number(attrs["r"], 0)
    )
  end

  defp element_path("ellipse", attrs) do
    ellipse_path(
      number(attrs["cx"], 0),
      number(attrs["cy"], 0),
      number(attrs["rx"], 0),
      number(attrs["ry"], 0)
    )
  end

  defp element_path(_name, _attrs), do: []

  defp ellipse_path(cx, cy, rx, ry) do
    [
      {:move_to, cx + rx, cy},
      {:curve_to, cx + rx, cy + @kappa * ry, cx + @kappa * rx, cy + ry, cx, cy + ry},
      {:curve_to, cx - @kappa * rx, cy + ry, cx - rx, cy + @kappa * ry, cx - rx, cy},
      {:curve_to, cx - rx, cy - @kappa * ry, cx - @kappa * rx, cy - ry, cx, cy - ry},
      {:curve_to, cx + @kappa * rx, cy - ry, cx + rx, cy - @kappa * ry, cx + rx, cy},
      :close
    ]
  end

  defp points_path(nil, _close?), do: []

  defp points_path(value, close?) do
    points =
      value
      |> numbers()
      |> Enum.chunk_every(2)
      |> Enum.filter(&(length(&1) == 2))

    case points do
      [] ->
        []

      [[x, y] | rest] ->
        [{:move_to, x, y}] ++
          Enum.map(rest, fn [px, py] -> {:line_to, px, py} end) ++
          if(close?, do: [:close], else: [])
    end
  end

  defp parse_path(data) do
    Regex.scan(~r/[MmLlHhVvCcQqZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?/, data)
    |> List.flatten()
    |> parse_path_tokens(nil, {0.0, 0.0}, {0.0, 0.0}, [])
    |> Enum.reverse()
  end

  defp parse_path_tokens([], _command, _point, _start, acc), do: acc

  defp parse_path_tokens([command | rest], _current, point, start, acc)
       when command in ~w(M m L l H h V v C c Q q Z z) do
    if command in ["Z", "z"] do
      parse_path_tokens(rest, nil, start, start, [:close | acc])
    else
      parse_path_tokens(rest, command, point, start, acc)
    end
  end

  defp parse_path_tokens(tokens, command, {x, y} = point, start, acc) do
    relative? = command == String.downcase(command)

    case {command, take_numbers(tokens, command_arity(command))} do
      {command, {values, rest}} when command in ["M", "m"] ->
        [px, py] = values
        target = absolute_point(px, py, point, relative?)
        next_command = if command == "m", do: "l", else: "L"

        parse_path_tokens(rest, next_command, target, target, [
          {:move_to, elem(target, 0), elem(target, 1)} | acc
        ])

      {command, {values, rest}} when command in ["L", "l"] ->
        [px, py] = values
        target = absolute_point(px, py, point, relative?)

        parse_path_tokens(rest, command, target, start, [
          {:line_to, elem(target, 0), elem(target, 1)} | acc
        ])

      {command, {[value], rest}} when command in ["H", "h"] ->
        target = if relative?, do: {x + value, y}, else: {value, y}

        parse_path_tokens(rest, command, target, start, [
          {:line_to, elem(target, 0), elem(target, 1)} | acc
        ])

      {command, {[value], rest}} when command in ["V", "v"] ->
        target = if relative?, do: {x, y + value}, else: {x, value}

        parse_path_tokens(rest, command, target, start, [
          {:line_to, elem(target, 0), elem(target, 1)} | acc
        ])

      {command, {[x1, y1, x2, y2, x3, y3], rest}} when command in ["C", "c"] ->
        p1 = absolute_point(x1, y1, point, relative?)
        p2 = absolute_point(x2, y2, point, relative?)
        p3 = absolute_point(x3, y3, point, relative?)

        segment =
          {:curve_to, elem(p1, 0), elem(p1, 1), elem(p2, 0), elem(p2, 1), elem(p3, 0),
           elem(p3, 1)}

        parse_path_tokens(rest, command, p3, start, [segment | acc])

      {command, {[x1, y1, x2, y2], rest}} when command in ["Q", "q"] ->
        control = absolute_point(x1, y1, point, relative?)
        target = absolute_point(x2, y2, point, relative?)
        c1 = {x + 2.0 / 3.0 * (elem(control, 0) - x), y + 2.0 / 3.0 * (elem(control, 1) - y)}

        c2 =
          {elem(target, 0) + 2.0 / 3.0 * (elem(control, 0) - elem(target, 0)),
           elem(target, 1) + 2.0 / 3.0 * (elem(control, 1) - elem(target, 1))}

        segment =
          {:curve_to, elem(c1, 0), elem(c1, 1), elem(c2, 0), elem(c2, 1), elem(target, 0),
           elem(target, 1)}

        parse_path_tokens(rest, command, target, start, [segment | acc])

      _ ->
        acc
    end
  end

  defp command_arity(command) when command in ["H", "h", "V", "v"], do: 1
  defp command_arity(command) when command in ["M", "m", "L", "l"], do: 2
  defp command_arity(command) when command in ["Q", "q"], do: 4
  defp command_arity(command) when command in ["C", "c"], do: 6
  defp command_arity(_command), do: 0

  defp take_numbers(tokens, count) do
    {raw, rest} = Enum.split(tokens, count)
    {Enum.map(raw, &number(&1, 0)), rest}
  end

  defp absolute_point(x, y, {cx, cy}, true), do: {cx + x, cy + y}
  defp absolute_point(x, y, _current, false), do: {x, y}

  defp viewbox_matrix(attrs, options) do
    x = Keyword.fetch!(options, :x)
    y = Keyword.fetch!(options, :y)
    width = Keyword.fetch!(options, :width)
    height = Keyword.fetch!(options, :height)

    case numbers(attrs["viewBox"]) do
      [vx, vy, vw, vh] when vw > 0 and vh > 0 ->
        scale = min(width / vw, height / vh)
        tx = x + (width - vw * scale) / 2 - vx * scale
        ty = y + (height - vh * scale) / 2 - vy * scale
        {scale, 0.0, 0.0, scale, tx, ty}

      _ ->
        source_width = max(number(attrs["width"], width), 1)
        source_height = max(number(attrs["height"], height), 1)
        {width / source_width, 0.0, 0.0, height / source_height, x, y}
    end
  end

  defp parse_transform(nil), do: @identity

  defp parse_transform(value) do
    Regex.scan(~r/(matrix|translate|scale|rotate)\s*\(([^)]*)\)/, value, capture: :all_but_first)
    |> Enum.reduce(@identity, fn [name, args], matrix ->
      multiply(matrix, transform_matrix(name, numbers(args)))
    end)
  end

  defp transform_matrix("matrix", [a, b, c, d, e, f]), do: {a, b, c, d, e, f}
  defp transform_matrix("translate", [x]), do: {1.0, 0.0, 0.0, 1.0, x, 0.0}
  defp transform_matrix("translate", [x, y]), do: {1.0, 0.0, 0.0, 1.0, x, y}
  defp transform_matrix("scale", [scale]), do: {scale, 0.0, 0.0, scale, 0.0, 0.0}
  defp transform_matrix("scale", [x, y]), do: {x, 0.0, 0.0, y, 0.0, 0.0}

  defp transform_matrix("rotate", [degrees]) do
    radians = degrees * :math.pi() / 180
    {:math.cos(radians), :math.sin(radians), -:math.sin(radians), :math.cos(radians), 0.0, 0.0}
  end

  defp transform_matrix("rotate", [degrees, cx, cy]) do
    multiply(
      multiply({1.0, 0.0, 0.0, 1.0, cx, cy}, transform_matrix("rotate", [degrees])),
      {1.0, 0.0, 0.0, 1.0, -cx, -cy}
    )
  end

  defp transform_matrix(_name, _values), do: @identity

  defp multiply({a1, b1, c1, d1, e1, f1}, {a2, b2, c2, d2, e2, f2}) do
    {
      a1 * a2 + c1 * b2,
      b1 * a2 + d1 * b2,
      a1 * c2 + c1 * d2,
      b1 * c2 + d1 * d2,
      a1 * e2 + c1 * f2 + e1,
      b1 * e2 + d1 * f2 + f1
    }
  end

  defp transform_path(segments, matrix) do
    Enum.map(segments, fn
      {:move_to, x, y} ->
        {px, py} = transform_point(x, y, matrix)
        {:move_to, px, py}

      {:line_to, x, y} ->
        {px, py} = transform_point(x, y, matrix)
        {:line_to, px, py}

      {:curve_to, x1, y1, x2, y2, x3, y3} ->
        {px1, py1} = transform_point(x1, y1, matrix)
        {px2, py2} = transform_point(x2, y2, matrix)
        {px3, py3} = transform_point(x3, y3, matrix)
        {:curve_to, px1, py1, px2, py2, px3, py3}

      :close ->
        :close
    end)
  end

  defp transform_point(x, y, {a, b, c, d, e, f}),
    do: {a * x + c * y + e, b * x + d * y + f}

  defp attributes(node) do
    node
    |> xml_element(:attributes)
    |> Map.new(fn attribute ->
      {attribute |> xml_attribute(:name) |> Atom.to_string(),
       attribute |> xml_attribute(:value) |> to_string()}
    end)
  end

  defp child_elements(node) do
    node
    |> xml_element(:content)
    |> Enum.filter(&(is_tuple(&1) and elem(&1, 0) == :xmlElement))
  end

  defp element_name(node), do: node |> xml_element(:name) |> Atom.to_string()

  defp xml_element(node, :name), do: elem(node, 1)
  defp xml_element(node, :attributes), do: elem(node, 7)
  defp xml_element(node, :content), do: elem(node, 8)
  defp xml_attribute(attribute, :name), do: elem(attribute, 1)
  defp xml_attribute(attribute, :value), do: elem(attribute, 8)

  defp numbers(nil), do: []

  defp numbers(value) do
    Regex.scan(~r/[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?/, value)
    |> List.flatten()
    |> Enum.map(&number(&1, 0))
  end

  defp number(nil, default), do: default

  defp number(value, default) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, _unit} -> number
      :error -> default
    end
  end

  defp color("none"), do: Color.black()
  defp color(nil), do: Color.black()

  defp color("#" <> <<r::binary-size(1), g::binary-size(1), b::binary-size(1)>>),
    do:
      Color.rgb255(
        String.to_integer(r <> r, 16),
        String.to_integer(g <> g, 16),
        String.to_integer(b <> b, 16)
      )

  defp color("#" <> <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>),
    do: Color.rgb255(String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16))

  defp color(value) do
    case numbers(value) do
      [r, g, b] -> Color.rgb255(round(r), round(g), round(b))
      _ -> named_color(String.downcase(value))
    end
  end

  defp named_color("white"), do: Color.white()
  defp named_color("red"), do: Color.rgb255(255, 0, 0)
  defp named_color("green"), do: Color.rgb255(0, 128, 0)
  defp named_color("blue"), do: Color.rgb255(0, 0, 255)
  defp named_color(_name), do: Color.black()

  defp svg_weight(value) when value in ["bold", "600", "700", "800", "900"], do: :bold
  defp svg_weight(_value), do: :regular
  defp svg_font_style("italic"), do: :italic
  defp svg_font_style("oblique"), do: :italic
  defp svg_font_style(_value), do: :normal
end
