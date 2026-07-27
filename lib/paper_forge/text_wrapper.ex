defmodule PaperForge.TextWrapper do
  @moduledoc """
  Wraps text into lines that fit within a maximum width.

  Text width is calculated using `PaperForge.TextMetrics`.
  Manual line breaks are preserved.
  """

  alias PaperForge.TextMetrics

  @type option ::
          {:width, number()}
          | {:font, atom()}
          | {:size, number()}

  @doc """
  Splits a string into lines that do not exceed the requested width.

  ## Examples

      PaperForge.TextWrapper.wrap(
        "PaperForge generates PDF documents directly in Elixir",
        width: 200,
        font: :helvetica,
        size: 12
      )
  """
  @spec wrap(binary(), [option()]) :: [binary()]
  def wrap(text, options)
      when is_binary(text) and is_list(options) do
    width = Keyword.fetch!(options, :width)

    validate_width!(width)

    text
    |> String.split("\n", trim: false)
    |> Enum.flat_map(fn paragraph ->
      wrap_paragraph(paragraph, options)
    end)
  end

  defp wrap_paragraph("", _options) do
    [""]
  end

  defp wrap_paragraph(paragraph, options) do
    paragraph
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.reduce([], fn word, lines ->
      append_word(lines, word, options)
    end)
    |> Enum.reverse()
  end

  defp append_word([], word, options) do
    word
    |> split_long_word(options)
    |> Enum.reverse()
  end

  defp append_word([current_line | remaining_lines], word, options) do
    candidate =
      if current_line == "" do
        word
      else
        current_line <> " " <> word
      end

    if fits?(candidate, options) do
      [candidate | remaining_lines]
    else
      word
      |> split_long_word(options)
      |> Enum.reduce(
        [current_line | remaining_lines],
        fn part, lines ->
          [part | lines]
        end
      )
    end
  end

  defp split_long_word(word, options) do
    if fits?(word, options) do
      [word]
    else
      word
      |> String.graphemes()
      |> Enum.reduce([""], fn grapheme, [current | rest] ->
        candidate = current <> grapheme

        cond do
          current == "" ->
            [candidate | rest]

          fits?(candidate, options) ->
            [candidate | rest]

          true ->
            [grapheme, current | rest]
        end
      end)
      |> Enum.reverse()
    end
  end

  defp fits?(text, options) do
    TextMetrics.line_width(
      text,
      font: Keyword.get(options, :font, :helvetica),
      font_instance: Keyword.get(options, :font_instance),
      size: Keyword.get(options, :size, 12)
    ) <= Keyword.fetch!(options, :width)
  end

  defp validate_width!(width)
       when is_number(width) and width > 0 do
    :ok
  end

  defp validate_width!(width) do
    raise ArgumentError,
          "text wrapping width must be greater than zero, received: " <>
            inspect(width)
  end
end
