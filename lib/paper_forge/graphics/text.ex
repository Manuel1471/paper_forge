defmodule PaperForge.Graphics.Text do
  @moduledoc """
  Builds PDF text drawing commands.
  """

  alias PaperForge.Color
  alias PaperForge.Graphics
  alias PaperForge.Serializer

  @default_font_name "F1"
  @default_font_size 12

  @spec command(binary(), keyword()) :: iodata()
  def command(text, options \\ []) when is_binary(text) do
    x = Keyword.get(options, :x, 0)
    y = Keyword.get(options, :y, 0)
    size = Keyword.get(options, :size, @default_font_size)
    font = Keyword.get(options, :font, @default_font_name)
    color = Keyword.get(options, :color, Color.black())

    validate_number!(:x, x)
    validate_number!(:y, y)
    validate_positive_number!(:size, size)

    [
      "q\n",
      Graphics.fill_color(color),
      "\nBT\n/",
      font,
      " ",
      Serializer.encode(size),
      " Tf\n",
      "1 0 0 1 ",
      Serializer.encode(x),
      " ",
      Serializer.encode(y),
      " Tm\n",
      Serializer.encode(text),
      " Tj\n",
      "ET\nQ"
    ]
  end

  defp validate_number!(_name, value) when is_number(value), do: :ok

  defp validate_number!(name, value) do
    raise ArgumentError,
          "#{name} must be a number, received: #{inspect(value)}"
  end

  defp validate_positive_number!(_name, value)
       when is_number(value) and value > 0,
       do: :ok

  defp validate_positive_number!(name, value) do
    raise ArgumentError,
          "#{name} must be greater than zero, received: #{inspect(value)}"
  end
end
