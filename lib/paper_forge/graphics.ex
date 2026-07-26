defmodule PaperForge.Graphics do
  @moduledoc false

  alias PaperForge.Color
  alias PaperForge.Serializer

  @spec stroke_color(Color.t()) :: iodata()
  def stroke_color(%Color{space: :rgb, components: [red, green, blue]}) do
    [
      number(red),
      " ",
      number(green),
      " ",
      number(blue),
      " RG"
    ]
  end

  def stroke_color(%Color{space: :gray, components: [gray]}) do
    [number(gray), " G"]
  end

  @spec fill_color(Color.t()) :: iodata()
  def fill_color(%Color{space: :rgb, components: [red, green, blue]}) do
    [
      number(red),
      " ",
      number(green),
      " ",
      number(blue),
      " rg"
    ]
  end

  def fill_color(%Color{space: :gray, components: [gray]}) do
    [number(gray), " g"]
  end

  @spec line_width(number()) :: iodata()
  def line_width(width) when is_number(width) and width >= 0 do
    [number(width), " w"]
  end

  def line_width(width) do
    raise ArgumentError,
          "line width must be a non-negative number, received: #{inspect(width)}"
  end

  @spec number(number()) :: iodata()
  def number(value), do: Serializer.encode(value)

  @spec paint_operator(boolean(), boolean()) :: binary()
  def paint_operator(true, true), do: "B"
  def paint_operator(true, false), do: "f"
  def paint_operator(false, true), do: "S"
  def paint_operator(false, false), do: "n"
end
