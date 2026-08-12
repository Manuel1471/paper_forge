defmodule PaperForge.Graphics.Text do
  @moduledoc """
  Builds PDF text drawing commands.

  Supports:

  - standard PDF fonts;
  - font size;
  - text color;
  - left, center, right, and justified alignment;
  - positioning inside a defined width.
  """

  alias PaperForge.Color
  alias PaperForge.Font
  alias PaperForge.FontError
  alias PaperForge.Fonts.TrueType
  alias PaperForge.Graphics
  alias PaperForge.Serializer
  alias PaperForge.TextMetrics

  @default_size 12
  @default_alignment :left

  @type option ::
          {:x, number()}
          | {:y, number()}
          | {:size, number()}
          | {:font, atom()}
          | {:font_instance, Font.t()}
          | {:resource_name, binary()}
          | {:color, Color.t()}
          | {:width, number()}
          | {:align, :left | :center | :right | :justify}

  @doc """
  Generates the PDF commands required to draw one line of text.

  Required options:

  - `:x`
  - `:y`
  - `:font`
  - `:resource_name`

  Optional options:

  - `:size`, defaults to `12`
  - `:color`, defaults to black
  - `:width`
  - `:align`, defaults to `:left`

  When `:width` is provided, the final X coordinate is calculated
  according to `:align`.

  ## Example

      PaperForge.Graphics.Text.command(
        "Centered title",
        x: 72,
        y: 740,
        width: 450,
        align: :center,
        font: :helvetica_bold,
        resource_name: "F2",
        size: 24
      )
  """
  @spec command(binary(), [option()]) :: iodata()
  def command(text, options)
      when is_binary(text) and is_list(options) do
    validate_options!(options)

    x =
      Keyword.fetch!(
        options,
        :x
      )

    y =
      Keyword.fetch!(
        options,
        :y
      )

    font =
      Keyword.fetch!(
        options,
        :font
      )

    font_instance =
      Keyword.get(
        options,
        :font_instance
      )

    resource_name =
      Keyword.fetch!(
        options,
        :resource_name
      )

    size =
      Keyword.get(
        options,
        :size,
        @default_size
      )

    color =
      Keyword.get(
        options,
        :color,
        Color.black()
      )

    width =
      Keyword.get(
        options,
        :width
      )

    alignment =
      Keyword.get(
        options,
        :align,
        @default_alignment
      )

    final_x =
      calculate_x(
        text,
        x,
        width,
        alignment,
        font_instance || font,
        size
      )

    encoded_text =
      encode_text(
        text,
        font,
        font_instance
      )

    word_spacing = word_spacing(text, width, alignment, font_instance || font, size)

    [
      "q\n",
      Graphics.fill_color(color),
      "\n",
      "BT\n",
      "/",
      resource_name,
      " ",
      Serializer.encode(size),
      " Tf\n",
      maybe_word_spacing(word_spacing),
      "1 0 0 1 ",
      Serializer.encode(final_x),
      " ",
      Serializer.encode(y),
      " Tm\n",
      Serializer.encode(encoded_text),
      " Tj\n",
      "ET\n",
      "Q"
    ]
  end

  defp encode_text(
         text,
         font_key,
         %Font{kind: :truetype} = font
       ) do
    glyph_data =
      text
      |> String.to_charlist()
      |> Enum.map(fn codepoint ->
        case TrueType.glyph_id(font, codepoint) do
          {:ok, glyph_id} ->
            <<glyph_id::16-big>>

          :error ->
            raise FontError, {:missing_glyph, font_key, codepoint}
        end
      end)

    {
      :hex_string,
      IO.iodata_to_binary(glyph_data)
    }
  end

  defp encode_text(text, _font_key, _font_instance) do
    text
  end

  defp calculate_x(
         _text,
         x,
         nil,
         :left,
         _font,
         _size
       ) do
    x
  end

  defp calculate_x(_text, x, _width, :justify, _font, _size), do: x

  defp calculate_x(
         _text,
         _x,
         nil,
         alignment,
         _font,
         _size
       )
       when alignment in [:center, :right] do
    raise ArgumentError,
          "text width is required when using #{inspect(alignment)} alignment"
  end

  defp calculate_x(
         text,
         x,
         width,
         alignment,
         font,
         size
       ) do
    TextMetrics.aligned_x(
      text,
      x,
      width,
      align: alignment,
      font: font,
      size: size
    )
  end

  defp word_spacing(text, width, :justify, font, size) when is_number(width) do
    spaces = text |> String.graphemes() |> Enum.count(&(&1 == " "))

    if spaces > 0 do
      extra = max(width - TextMetrics.line_width(text, font: font, size: size), 0)
      extra / spaces / size
    else
      0
    end
  end

  defp word_spacing(_text, _width, _alignment, _font, _size), do: 0

  defp maybe_word_spacing(0), do: []
  defp maybe_word_spacing(value), do: [Serializer.encode(value), " Tw\n"]

  defp validate_options!(options) do
    validate_required_option!(
      options,
      :x
    )

    validate_required_option!(
      options,
      :y
    )

    validate_required_option!(
      options,
      :font
    )

    validate_required_option!(
      options,
      :resource_name
    )

    validate_number!(
      :x,
      Keyword.fetch!(options, :x)
    )

    validate_number!(
      :y,
      Keyword.fetch!(options, :y)
    )

    validate_resource_name!(Keyword.fetch!(options, :resource_name))

    validate_positive_number!(
      :size,
      Keyword.get(options, :size, @default_size)
    )

    validate_alignment!(Keyword.get(options, :align, @default_alignment))

    validate_optional_width!(Keyword.get(options, :width))

    validate_single_line!(options)
  end

  defp validate_required_option!(options, option) do
    unless Keyword.has_key?(options, option) do
      raise ArgumentError,
            "missing required text option #{inspect(option)}"
    end
  end

  defp validate_number!(_name, value)
       when is_number(value) do
    :ok
  end

  defp validate_number!(name, value) do
    raise ArgumentError,
          "#{name} must be a number, received: #{inspect(value)}"
  end

  defp validate_positive_number!(_name, value)
       when is_number(value) and value > 0 do
    :ok
  end

  defp validate_positive_number!(name, value) do
    raise ArgumentError,
          "#{name} must be greater than zero, received: #{inspect(value)}"
  end

  defp validate_resource_name!(resource_name)
       when is_binary(resource_name) and
              byte_size(resource_name) > 0 do
    :ok
  end

  defp validate_resource_name!(resource_name) do
    raise ArgumentError,
          "resource_name must be a non-empty string, received: " <>
            inspect(resource_name)
  end

  defp validate_alignment!(alignment)
       when alignment in [:left, :center, :right, :justify] do
    :ok
  end

  defp validate_alignment!(alignment) do
    raise ArgumentError,
          "unsupported text alignment #{inspect(alignment)}. " <>
            "Expected :left, :center, :right, or :justify"
  end

  defp validate_optional_width!(nil) do
    :ok
  end

  defp validate_optional_width!(width)
       when is_number(width) and width > 0 do
    :ok
  end

  defp validate_optional_width!(width) do
    raise ArgumentError,
          "text width must be greater than zero, received: " <>
            inspect(width)
  end

  defp validate_single_line!(options) do
    case Keyword.get(options, :multiline, false) do
      false ->
        :ok

      true ->
        raise ArgumentError,
              "use PaperForge.Graphics.TextBox for multiline text"
    end
  end
end
