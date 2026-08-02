defmodule PaperForge.Import.CSS do
  @moduledoc """
  Validated CSS subset used by the HTML importer.

  Supported selectors are element names, `.class`, and `#id`. Supported
  declarations include typography, colors, dimensions, vertical spacing,
  page breaks, and practical table properties such as padding, line height,
  borders, border collapse, and vertical alignment.
  """

  import Bitwise

  @properties ~w(color background-color font-family font-size font-weight font-style text-align text-transform vertical-align line-height padding border-color border-width border-style border-collapse margin-top margin-bottom width max-width height display visibility list-style-type object-fit object-position hyphens widows orphans break-before break-after break-inside page-break-before page-break-after page-break-inside)

  @spec parse(binary(), keyword()) :: {:ok, list()} | {:error, term()}
  def parse(source, options \\ []) when is_binary(source) do
    strict? = Keyword.get(options, :strict, true)

    source
    |> String.replace(~r{/\*.*?\*/}s, "")
    |> then(&Regex.scan(~r/([^{}]+)\{([^{}]*)\}/, &1, capture: :all_but_first))
    |> Enum.reduce_while({:ok, []}, fn [selectors, body], {:ok, rules} ->
      with {:ok, declarations} <- declarations(body, strict?) do
        parsed =
          selectors
          |> String.split(",", trim: true)
          |> Enum.map(&{String.trim(&1), declarations})

        {:cont, {:ok, rules ++ parsed}}
      else
        error -> {:halt, error}
      end
    end)
  end

  @spec declarations(binary(), boolean()) :: {:ok, map()} | {:error, term()}
  def declarations(source, strict? \\ true) do
    source
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce_while({:ok, %{}}, fn declaration, {:ok, styles} ->
      case String.split(declaration, ":", parts: 2) do
        [name, value] ->
          name = name |> String.trim() |> String.downcase()

          cond do
            name in @properties ->
              {:cont, {:ok, Map.put(styles, name, String.trim(value))}}

            strict? ->
              {:halt, {:error, {:unsupported_css_property, name}}}

            true ->
              {:cont, {:ok, styles}}
          end

        _ ->
          {:halt, {:error, {:invalid_css_declaration, String.trim(declaration)}}}
      end
    end)
  end

  @spec styles_for(map(), list(), map()) :: map()
  def styles_for(node, rules, inherited \\ %{}) do
    matched =
      Enum.reduce(rules, %{}, fn {selector, declarations}, styles ->
        if matches?(node, selector), do: Map.merge(styles, declarations), else: styles
      end)

    inline = Map.get(node.attrs, "style", "")

    inline_styles =
      case declarations(inline, false) do
        {:ok, styles} -> styles
        _ -> %{}
      end

    inherited
    |> Map.take(~w(color font-size font-weight font-style text-align))
    |> Map.merge(matched)
    |> Map.merge(inline_styles)
  end

  @spec to_options(map()) :: keyword()
  def to_options(styles) do
    []
    |> put_color(:color, styles["color"])
    |> put_color(:fill_color, styles["background-color"])
    |> put_length(:size, styles["font-size"])
    |> put_length(:space_before, styles["margin-top"])
    |> put_length(:space_after, styles["margin-bottom"])
    |> put_width(styles["width"])
    |> put_max_width(styles["width"], styles["max-width"])
    |> put_length(:height, styles["height"])
    |> put_length(:padding, styles["padding"])
    |> put_length(:line_height, styles["line-height"])
    |> put_color(:stroke_color, styles["border-color"])
    |> put_length(:line_width, styles["border-width"])
    |> put_border_style(styles["border-style"])
    |> put_font(styles["font-family"])
    |> put_fit(styles["object-fit"])
    |> put_object_position(styles["object-position"])
    |> put_boolean(:hyphenate, styles["hyphens"], "auto")
    |> put_boolean(:keep_together, styles["break-inside"] || styles["page-break-inside"], "avoid")
    |> put_integer(:min_lines_at_top, styles["widows"])
    |> put_integer(:min_lines_at_bottom, styles["orphans"])
    |> put_enum(:weight, styles["font-weight"], %{"bold" => :bold, "700" => :bold})
    |> put_enum(:style, styles["font-style"], %{"italic" => :italic})
    |> put_enum(:align, styles["text-align"], %{
      "left" => :left,
      "center" => :center,
      "right" => :right,
      "justify" => :justify
    })
    |> put_enum(:valign, styles["vertical-align"], %{
      "top" => :top,
      "middle" => :middle,
      "bottom" => :bottom
    })
  end

  @doc false
  @spec selector_styles(list(), [binary()]) :: map()
  def selector_styles(rules, selectors) do
    Enum.reduce(rules, %{}, fn {selector, declarations}, styles ->
      if String.trim(selector) in selectors,
        do: Map.merge(styles, declarations),
        else: styles
    end)
  end

  @doc false
  @spec table_options(map(), map(), map(), map()) :: keyword()
  def table_options(table, header, cell, stripe) do
    to_options(table)
    |> rename_option(:fill_color, :body_fill_color)
    |> put_color(:stroke_color, table["border-color"])
    |> put_length(:line_width, table["border-width"])
    |> put_border_style(table["border-style"])
    |> put_color(:header_fill_color, header["background-color"])
    |> put_color(:header_color, header["color"])
    |> put_color(:body_fill_color, cell["background-color"])
    |> put_color(:stripe_fill_color, stripe["background-color"])
    |> put_length(:padding, cell["padding"] || header["padding"] || table["padding"])
    |> put_length(
      :cell_line_height,
      cell["line-height"] || header["line-height"] || table["line-height"]
    )
    |> put_enum(:cell_align, cell["text-align"] || header["text-align"], %{
      "left" => :left,
      "center" => :center,
      "right" => :right,
      "justify" => :justify
    })
    |> put_enum(:cell_valign, cell["vertical-align"] || header["vertical-align"], %{
      "top" => :top,
      "middle" => :middle,
      "bottom" => :bottom
    })
  end

  defp matches?(node, "." <> class) do
    class in String.split(Map.get(node.attrs, "class", ""), ~r/\s+/, trim: true)
  end

  defp matches?(node, "#" <> id), do: Map.get(node.attrs, "id") == id
  defp matches?(_node, "*"), do: true

  defp matches?(node, selector) do
    {tag_and_classes, id} =
      case String.split(selector, "#", parts: 2) do
        [left, right] -> {left, right}
        [left] -> {left, nil}
      end

    [tag | classes] = String.split(tag_and_classes, ".", trim: false)
    node_classes = String.split(Map.get(node.attrs, "class", ""), ~r/\s+/, trim: true)

    tag_matches? = tag == "" or node.tag == String.downcase(tag)
    classes_match? = Enum.all?(classes, &(&1 in node_classes))
    id_matches? = is_nil(id) or Map.get(node.attrs, "id") == id

    tag_matches? and classes_match? and id_matches?
  end

  defp put_color(options, _key, nil), do: options

  defp put_color(options, key, "#" <> hex) when byte_size(hex) == 6 do
    {value, ""} = Integer.parse(hex, 16)

    Keyword.put(
      options,
      key,
      PaperForge.Color.rgb255(value >>> 16, value >>> 8 &&& 255, value &&& 255)
    )
  end

  defp put_color(options, _key, _value), do: options

  defp put_length(options, _key, nil), do: options

  defp put_length(options, key, value) do
    case Float.parse(String.replace(value, ~r/(px|pt|em|rem|%)$/, "")) do
      {number, ""} -> Keyword.put(options, key, number)
      _ -> options
    end
  end

  defp put_width(options, nil), do: options

  defp put_width(options, value) when value in ["100%", "100.0%"],
    do: Keyword.put(options, :width, :content)

  defp put_width(options, "%" <> _value), do: options

  defp put_width(options, value) do
    if String.ends_with?(value, "%"),
      do: options,
      else: put_length(options, :width, value)
  end

  defp put_max_width(options, width, value) when not is_nil(width) or is_nil(value), do: options
  defp put_max_width(options, _width, value), do: put_width(options, value)

  defp put_enum(options, _key, nil, _values), do: options
  defp put_enum(options, key, value, values), do: maybe_put(options, key, values[value])
  defp maybe_put(options, _key, nil), do: options
  defp maybe_put(options, key, value), do: Keyword.put(options, key, value)

  defp rename_option(options, old, new) do
    case Keyword.pop(options, old) do
      {nil, remaining} -> remaining
      {value, remaining} -> Keyword.put(remaining, new, value)
    end
  end

  defp put_border_style(options, "none"), do: Keyword.put(options, :line_width, 0)
  defp put_border_style(options, _style), do: options

  defp put_font(options, nil), do: options

  defp put_font(options, value) do
    family = value |> String.trim(~s("')) |> String.downcase()

    font =
      cond do
        String.contains?(family, "times") or String.contains?(family, "serif") ->
          :times_roman

        String.contains?(family, "courier") or String.contains?(family, "monospace") ->
          :courier

        String.contains?(family, "helvetica") or String.contains?(family, "sans-serif") ->
          :helvetica

        true ->
          nil
      end

    maybe_put(options, :font, font)
  end

  defp put_fit(options, "contain"), do: Keyword.put(options, :fit, :contain)
  defp put_fit(options, "cover"), do: Keyword.put(options, :fit, :cover)
  defp put_fit(options, "fill"), do: Keyword.put(options, :fit, :fill)
  defp put_fit(options, _value), do: options

  defp put_object_position(options, nil), do: options

  defp put_object_position(options, value) do
    words = String.split(String.downcase(value), ~r/\s+/, trim: true)

    options
    |> maybe_put(
      :align,
      Enum.find_value(
        words,
        &Map.get(%{"left" => :left, "center" => :center, "right" => :right}, &1)
      )
    )
    |> maybe_put(
      :valign,
      Enum.find_value(
        words,
        &Map.get(%{"top" => :top, "center" => :middle, "bottom" => :bottom}, &1)
      )
    )
  end

  defp put_boolean(options, _key, nil, _truthy), do: options
  defp put_boolean(options, key, value, truthy), do: Keyword.put(options, key, value == truthy)

  defp put_integer(options, _key, nil), do: options

  defp put_integer(options, key, value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> Keyword.put(options, key, number)
      _ -> options
    end
  end
end
