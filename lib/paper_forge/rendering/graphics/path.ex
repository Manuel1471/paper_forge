defmodule PaperForge.Graphics.Path do
  @moduledoc """
  Builds PDF path commands from move, line, cubic curve, and close operations.
  """

  alias PaperForge.Graphics
  alias PaperForge.Serializer

  @type segment ::
          {:move_to, number(), number()}
          | {:line_to, number(), number()}
          | {:curve_to, number(), number(), number(), number(), number(), number()}
          | :close

  @spec command([segment()], keyword()) :: iodata()
  def command(segments, options) when is_list(segments) and is_list(options) do
    fill? = Keyword.get(options, :fill, false)
    stroke? = Keyword.get(options, :stroke, true)

    [
      "q\n",
      maybe_clip(Keyword.get(options, :clip_path)),
      Graphics.fill_color(Keyword.get(options, :fill_color, PaperForge.Color.black())),
      "\n",
      Graphics.stroke_color(Keyword.get(options, :stroke_color, PaperForge.Color.black())),
      "\n",
      Serializer.encode(Keyword.get(options, :line_width, 1)),
      " w\n",
      Enum.map(segments, &segment/1),
      paint_operator(fill?, stroke?, Keyword.get(options, :fill_rule, :nonzero)),
      "\nQ"
    ]
  end

  defp maybe_clip(nil), do: []

  defp maybe_clip(segments) do
    [Enum.map(segments, &segment/1), "W n\n"]
  end

  defp segment({:move_to, x, y}), do: [number(x), " ", number(y), " m\n"]
  defp segment({:line_to, x, y}), do: [number(x), " ", number(y), " l\n"]

  defp segment({:curve_to, x1, y1, x2, y2, x3, y3}),
    do: [
      number(x1),
      " ",
      number(y1),
      " ",
      number(x2),
      " ",
      number(y2),
      " ",
      number(x3),
      " ",
      number(y3),
      " c\n"
    ]

  defp segment(:close), do: "h\n"

  defp paint_operator(true, true, :evenodd), do: "B*"
  defp paint_operator(true, false, :evenodd), do: "f*"
  defp paint_operator(true, true, _rule), do: "B"
  defp paint_operator(true, false, _rule), do: "f"
  defp paint_operator(false, true, _rule), do: "S"
  defp paint_operator(false, false, _rule), do: "n"

  defp number(value), do: Serializer.encode(value)
end
