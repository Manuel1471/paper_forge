defmodule PaperForge.Graphics.Circle do
  @moduledoc """
  Builds PDF commands for drawing circles using cubic Bézier curves.
  """

  alias PaperForge.Color
  alias PaperForge.Graphics

  @bezier_constant 0.552_284_749_8

  @spec command(keyword()) :: iodata()
  def command(options) do
    center_x = fetch_number!(options, :x)
    center_y = fetch_number!(options, :y)
    radius = fetch_positive_number!(options, :radius)

    stroke = Keyword.get(options, :stroke, true)
    fill = Keyword.get(options, :fill, false)

    stroke_color = Keyword.get(options, :stroke_color, Color.black())
    fill_color = Keyword.get(options, :fill_color, Color.white())
    line_width = Keyword.get(options, :line_width, 1)

    control = radius * @bezier_constant

    left = center_x - radius
    right = center_x + radius
    bottom = center_y - radius
    top = center_y + radius

    [
      "q\n",
      optional(fill, Graphics.fill_color(fill_color)),
      optional(stroke, Graphics.stroke_color(stroke_color)),
      optional(stroke, Graphics.line_width(line_width)),
      point(center_x, top),
      " m\n",
      curve(
        center_x + control,
        top,
        right,
        center_y + control,
        right,
        center_y
      ),
      "\n",
      curve(
        right,
        center_y - control,
        center_x + control,
        bottom,
        center_x,
        bottom
      ),
      "\n",
      curve(
        center_x - control,
        bottom,
        left,
        center_y - control,
        left,
        center_y
      ),
      "\n",
      curve(
        left,
        center_y + control,
        center_x - control,
        top,
        center_x,
        top
      ),
      "\n",
      "h\n",
      Graphics.paint_operator(fill, stroke),
      "\nQ"
    ]
  end

  defp point(x, y) do
    [Graphics.number(x), " ", Graphics.number(y)]
  end

  defp curve(x1, y1, x2, y2, x3, y3) do
    [
      point(x1, y1),
      " ",
      point(x2, y2),
      " ",
      point(x3, y3),
      " c"
    ]
  end

  defp optional(true, command), do: [command, "\n"]
  defp optional(false, _command), do: []

  defp fetch_number!(options, name) do
    case Keyword.fetch(options, name) do
      {:ok, value} when is_number(value) -> value
      {:ok, value} -> raise ArgumentError, "#{name} must be a number: #{inspect(value)}"
      :error -> raise ArgumentError, "missing required option #{inspect(name)}"
    end
  end

  defp fetch_positive_number!(options, name) do
    value = fetch_number!(options, name)

    if value > 0 do
      value
    else
      raise ArgumentError, "#{name} must be greater than zero"
    end
  end
end
