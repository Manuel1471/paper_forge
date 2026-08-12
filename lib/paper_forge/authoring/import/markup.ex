defmodule PaperForge.Import.Markup do
  @moduledoc false

  alias PaperForge.Flow
  alias PaperForge.Import.CSS

  @spec to_flow([map()], keyword()) :: {:ok, Flow.t()} | {:error, term()}
  def to_flow(nodes, options \\ []) do
    rules = Keyword.get(options, :css_rules, [])
    {:ok, render_nodes(Flow.new(), nodes, rules, %{})}
  rescue
    exception in [ArgumentError] -> {:error, Exception.message(exception)}
  end

  defp render_nodes(flow, nodes, rules, inherited) do
    Enum.reduce(nodes, flow, fn node, current -> render_node(current, node, rules, inherited) end)
  end

  defp render_node(flow, %{tag: "#text"}, _rules, _inherited), do: flow

  defp render_node(flow, node, rules, inherited) do
    styles = CSS.styles_for(node, rules, inherited)
    options = CSS.to_options(styles)
    hidden? = styles["display"] == "none" or styles["visibility"] == "hidden"

    flow =
      if break_before?(styles) and not hidden?, do: Flow.page_break(flow), else: flow

    flow =
      if hidden? do
        flow
      else
        case node.tag do
          "h" <> level when level in ~w(1 2 3 4 5 6) ->
            Flow.heading(
              flow,
              styled_text(node, styles),
              Keyword.put(options, :level, String.to_integer(level))
            )

          "p" ->
            Flow.paragraph(flow, styled_text(node, styles), options)

          "blockquote" ->
            Flow.paragraph(
              flow,
              styled_text(node, styles),
              Keyword.merge([indent: 20, color: PaperForge.Color.gray(0.35)], options)
            )

          "pre" ->
            Flow.paragraph(
              flow,
              styled_text(node, styles),
              Keyword.merge([font: :courier, size: 8.5], options)
            )

          tag when tag in ["ul", "ol"] ->
            items =
              node.children
              |> Enum.filter(&(&1.tag == "li"))
              |> Enum.map(fn item -> styled_text(item, CSS.styles_for(item, rules, styles)) end)

            list_type =
              case styles["list-style-type"] do
                value when value in ["decimal", "decimal-leading-zero"] -> :ordered
                value when value in ["none"] -> :none
                _ -> if(tag == "ol", do: :ordered, else: :unordered)
              end

            Flow.list(
              flow,
              items,
              Keyword.put(options, :type, list_type)
            )

          "table" ->
            {columns, rows, css_options} = table(node, rules, styles)

            Flow.table(
              flow,
              columns,
              rows,
              imported_table_options(Keyword.merge(options, css_options))
            )

          "img" ->
            case node.attrs["src"] do
              nil -> flow
              source -> Flow.image(flow, source, options)
            end

          "svg" ->
            case node.raw do
              nil -> flow
              source -> Flow.svg(flow, source, options)
            end

          tag when tag in ["style", "script", "head", "title"] ->
            flow

          _ ->
            render_nodes(flow, node.children, rules, styles)
        end
      end

    if break_after?(styles) and not hidden?, do: Flow.page_break(flow), else: flow
  end

  defp table(node, rules, inherited) do
    rows = descendants(node, "tr")

    parsed =
      Enum.map(rows, fn row ->
        row.children
        |> Enum.filter(&(&1.tag in ["th", "td"]))
        |> Enum.map(fn cell ->
          cell_styles = CSS.styles_for(cell, rules, inherited)
          cell_options = CSS.to_options(cell_styles)

          Flow.cell(styled_text(cell, cell_styles),
            align: cell_options[:align],
            valign: cell_options[:valign],
            fill_color: cell_options[:fill_color],
            color: cell_options[:color]
          )
        end)
      end)

    header_node = descendants(node, "th") |> List.first()
    cell_node = descendants(node, "td") |> List.first()
    header_styles = if(header_node, do: CSS.styles_for(header_node, rules, inherited), else: %{})
    cell_styles = if(cell_node, do: CSS.styles_for(cell_node, rules, inherited), else: %{})

    stripe_styles =
      CSS.selector_styles(rules, [
        "tr:nth-child(even)",
        "tbody tr:nth-child(even)",
        "tr:nth-child(even) td",
        "tbody tr:nth-child(even) td"
      ])

    css_options = CSS.table_options(inherited, header_styles, cell_styles, stripe_styles)

    case parsed do
      [columns | data] -> {columns, data, css_options}
      [] -> {[], [], css_options}
    end
  end

  defp imported_table_options(options) do
    defaults = [
      repeat_header: true,
      padding: 9,
      row_height: 32,
      cell_line_height: 12,
      size: 8.5,
      cell_valign: :middle,
      header_fill_color: PaperForge.Color.rgb255(21, 54, 74),
      header_color: PaperForge.Color.white(),
      stripe_fill_color: PaperForge.Color.rgb255(246, 249, 248),
      stroke_color: PaperForge.Color.rgb255(207, 218, 217),
      line_width: 0.4
    ]

    Enum.reduce(defaults, options, fn {key, value}, current ->
      Keyword.put_new(current, key, value)
    end)
  end

  defp descendants(node, tag) do
    direct = Enum.filter(node.children, &(&1.tag == tag))
    direct ++ Enum.flat_map(node.children, &descendants(&1, tag))
  end

  defp text(%{tag: "#text", text: value}), do: value

  defp text(node) do
    node.children
    |> Enum.map(&text/1)
    |> Enum.join("")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp styled_text(node, styles) do
    value = text(node)

    case styles["text-transform"] do
      "uppercase" -> String.upcase(value)
      "lowercase" -> String.downcase(value)
      "capitalize" -> value |> String.split() |> Enum.map_join(" ", &String.capitalize/1)
      _ -> value
    end
  end

  defp break_before?(styles),
    do: styles["page-break-before"] == "always" or styles["break-before"] in ["page", "always"]

  defp break_after?(styles),
    do: styles["page-break-after"] == "always" or styles["break-after"] in ["page", "always"]
end
