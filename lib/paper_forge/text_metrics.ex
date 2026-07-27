defmodule PaperForge.TextMetrics do
  @moduledoc """
  Measures text using the metrics of the standard PDF fonts.

  Measurements are returned in PDF points.
  """

  alias PaperForge.Fonts.Builtin
  alias PaperForge.Fonts.Metrics
  alias PaperForge.Fonts.TrueType

  @default_font :helvetica
  @default_size 12

  @type alignment ::
          :left
          | :center
          | :right

  @doc """
  Returns the width of a text string in PDF points.

  When the string contains multiple lines, the width of the longest
  line is returned.

  ## Examples

      PaperForge.TextMetrics.width(
        "Hello",
        font: :helvetica,
        size: 12
      )
  """
  @spec width(binary(), keyword()) :: float()
  def width(text, options \\ [])
      when is_binary(text) and is_list(options) do
    font = font_option(options)

    size =
      Keyword.get(
        options,
        :size,
        @default_size
      )

    validate_font!(font)
    validate_size!(size)

    text
    |> String.split("\n")
    |> Enum.map(&line_width(&1, font: font, size: size))
    |> Enum.max(fn -> 0.0 end)
  end

  @doc """
  Returns the width of one line of text in PDF points.
  """
  @spec line_width(binary(), keyword()) :: float()
  def line_width(text, options \\ [])
      when is_binary(text) and is_list(options) do
    font = font_option(options)

    size =
      Keyword.get(
        options,
        :size,
        @default_size
      )

    validate_font!(font)
    validate_size!(size)

    text
    |> String.to_charlist()
    |> Enum.reduce(0, fn codepoint, total ->
      total + glyph_width(font, codepoint)
    end)
    |> then(fn width_in_font_units ->
      width_in_font_units * size / 1000
    end)
  end

  @doc """
  Calculates the final X coordinate for horizontally aligned text.

  The provided `x` and `container_width` define the horizontal box.

  ## Examples

      PaperForge.TextMetrics.aligned_x(
        "Centered",
        72,
        450,
        align: :center,
        font: :helvetica,
        size: 18
      )
  """
  @spec aligned_x(
          binary(),
          number(),
          number(),
          keyword()
        ) :: float()
  def aligned_x(
        text,
        x,
        container_width,
        options \\ []
      )
      when is_binary(text) and
             is_number(x) and
             is_number(container_width) and
             is_list(options) do
    align =
      Keyword.get(
        options,
        :align,
        :left
      )

    validate_alignment!(align)
    validate_container_width!(container_width)

    text_width =
      line_width(text, options)

    case align do
      :left ->
        x * 1.0

      :center ->
        x + (container_width - text_width) / 2

      :right ->
        x + container_width - text_width
    end
  end

  defp font_option(options) do
    case Keyword.get(options, :font_instance) do
      nil ->
        Keyword.get(options, :font, @default_font)

      font_instance ->
        font_instance
    end
  end

  defp validate_font!(%PaperForge.Font{kind: :truetype}) do
    :ok
  end

  defp validate_font!(%PaperForge.Font{kind: :builtin, key: font_key}) do
    validate_font!(font_key)
  end

  defp validate_font!(font) do
    Builtin.fetch!(font)
    :ok
  end

  defp glyph_width(%PaperForge.Font{kind: :truetype} = font, codepoint) do
    case TrueType.glyph_id(font, codepoint) do
      {:ok, glyph_id} ->
        TrueType.pdf_width(font, glyph_id)

      :error ->
        0
    end
  end

  defp glyph_width(%PaperForge.Font{kind: :builtin, key: font_key}, codepoint) do
    glyph_width(font_key, codepoint)
  end

  defp glyph_width(font, codepoint) do
    Metrics.width(font, codepoint)
  end

  defp validate_size!(size)
       when is_number(size) and size > 0 do
    :ok
  end

  defp validate_size!(size) do
    raise ArgumentError,
          "font size must be greater than zero, received: #{inspect(size)}"
  end

  defp validate_container_width!(width)
       when width >= 0 do
    :ok
  end

  defp validate_container_width!(width) do
    raise ArgumentError,
          "container width must be non-negative, received: #{inspect(width)}"
  end

  defp validate_alignment!(alignment)
       when alignment in [:left, :center, :right] do
    :ok
  end

  defp validate_alignment!(alignment) do
    raise ArgumentError,
          "unsupported text alignment #{inspect(alignment)}. " <>
            "Expected :left, :center, or :right"
  end
end
