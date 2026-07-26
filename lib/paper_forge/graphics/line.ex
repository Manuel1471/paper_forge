defmodule PaperForge.Graphics.Line do
  @moduledoc """
  Builds PDF commands for drawing lines.
  """

  alias PaperForge.Color
  alias PaperForge.Graphics

  @spec command(keyword()) :: iodata()
  def command(options) do
    x1 = fetch_number!(options, :x1)
    y1 = fetch_number!(options, :y1)
    x2 = fetch_number!(options, :x2)
    y2 = fetch_number!(options, :y2)

    width = Keyword.get(options, :width, 1)
    color = Keyword.get(options, :color, Color.black())

    [
      "q\n",
      Graphics.stroke_color(color),
      "\n",
      Graphics.line_width(width),
      "\n",
      Graphics.number(x1),
      " ",
      Graphics.number(y1),
      " m\n",
      Graphics.number(x2),
      " ",
      Graphics.number(y2),
      " l\n",
      "S\n",
      "Q"
    ]
  end

  defp fetch_number!(options, name) do
    case Keyword.fetch(options, name) do
      {:ok, value} when is_number(value) ->
        value

      {:ok, value} ->
        raise ArgumentError,
              "#{name} must be a number, received: #{inspect(value)}"

      :error ->
        raise ArgumentError, "missing required option #{inspect(name)}"
    end
  end
end
