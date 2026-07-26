defmodule PaperForge.Graphics.Rectangle do
  @moduledoc """
  Builds PDF commands for drawing rectangles.
  """

  alias PaperForge.Color
  alias PaperForge.Graphics

  @spec command(keyword()) :: iodata()
  def command(options) do
    x = fetch_number!(options, :x)
    y = fetch_number!(options, :y)
    width = fetch_positive_number!(options, :width)
    height = fetch_positive_number!(options, :height)

    stroke = Keyword.get(options, :stroke, true)
    fill = Keyword.get(options, :fill, false)

    stroke_color = Keyword.get(options, :stroke_color, Color.black())
    fill_color = Keyword.get(options, :fill_color, Color.white())
    line_width = Keyword.get(options, :line_width, 1)

    [
      "q\n",
      optional_color(fill, Graphics.fill_color(fill_color)),
      optional_color(stroke, Graphics.stroke_color(stroke_color)),
      optional_color(stroke, Graphics.line_width(line_width)),
      Graphics.number(x),
      " ",
      Graphics.number(y),
      " ",
      Graphics.number(width),
      " ",
      Graphics.number(height),
      " re\n",
      Graphics.paint_operator(fill, stroke),
      "\nQ"
    ]
  end

  defp optional_color(true, command), do: [command, "\n"]
  defp optional_color(false, _command), do: []

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
