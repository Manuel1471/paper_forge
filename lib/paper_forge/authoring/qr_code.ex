defmodule PaperForge.QRCode do
  @moduledoc """
  Vector QR codes with a square size in points, error correction (`:l`, `:m`,
  `:q`, `:h`), and a quiet zone of at least four modules. No network requests
  or image files are needed. The payload is encoded verbatim.
  """
  alias PaperForge.Color
  alias PaperForge.Page

  @doc "Resolves and validates the square size, retaining legacy width/height options."
  def size!(options) do
    size =
      Keyword.get(
        options,
        :size,
        min(Keyword.get(options, :width, 120), Keyword.get(options, :height, 120))
      )

    unless is_number(size) and size > 0, do: raise(ArgumentError, "QR size must be positive")
    size
  end

  @doc "Draws a QR code at x/y in the page coordinate system."
  def draw(page, data, options) when is_binary(data) and byte_size(data) > 0 do
    size = size!(options)
    level = Keyword.get(options, :level, :m)
    quiet = Keyword.get(options, :quiet_zone, 4)
    unless level in [:l, :m, :q, :h], do: raise(ArgumentError, "invalid QR correction level")

    unless is_integer(quiet) and quiet >= 4 and quiet <= 32,
      do: raise(ArgumentError, "QR quiet_zone must be an integer from 4 to 32")

    x = Keyword.get(options, :x, Page.content_left(page))
    y = Keyword.get(options, :y, 0)
    origin = Keyword.get(options, :origin, page.origin)
    matrix = Qiroex.to_matrix!(data, level: level, quiet_zone: quiet)
    count = length(matrix)
    unit = size / count

    segments =
      matrix
      |> Enum.with_index()
      |> Enum.flat_map(fn {row, index} ->
        row_y = if origin == :top_left, do: y + index * unit, else: y + (count - index - 1) * unit

        row_segments(row, x, row_y, unit)
      end)

    background = Keyword.get(options, :background_color, Color.white())

    page =
      if background do
        Page.rectangle(page,
          x: x,
          y: y,
          width: size,
          height: size,
          origin: origin,
          fill: true,
          stroke: false,
          fill_color: background
        )
      else
        page
      end

    Page.path(page, segments,
      origin: origin,
      fill: true,
      stroke: false,
      fill_color: Keyword.get(options, :color, Color.black())
    )
  end

  def draw(_page, _data, _options),
    do: raise(ArgumentError, "QR payload must be a nonempty string")

  defp row_segments(row, x, y, unit) do
    {paths, _column} =
      row
      |> Enum.chunk_by(& &1)
      |> Enum.map_reduce(0, fn run, column ->
        count = length(run)

        path =
          if hd(run) == 1, do: [{:rectangle, x + column * unit, y, count * unit, unit}], else: []

        {path, column + count}
      end)

    List.flatten(paths)
  end
end
