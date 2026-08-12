defmodule PaperForge.Graphics.TextBox do
  @moduledoc """
  Builds multiline text commands constrained to a rectangular area.

  This module handles:

  - automatic word wrapping;
  - line height;
  - horizontal alignment;
  - optional height limits;
  - overflow detection.

  It does not draw a visible rectangle. It only generates the text
  commands required for the box.
  """

  alias PaperForge.Graphics.Text
  alias PaperForge.TextWrapper

  @default_size 12

  @type result :: %{
          commands: iodata(),
          lines: [binary()],
          remaining_lines: [binary()],
          overflow?: boolean(),
          consumed_height: number()
        }

  @doc """
  Generates PDF text commands for a multiline text box.

  Required options:

  - `:x`
  - `:y`
  - `:width`
  - `:resource_name`
  - `:font`

  Optional options:

  - `:height`
  - `:size`
  - `:line_height`
  - `:align`
  - `:color`
  - `:font_instance`

  ## Example

      PaperForge.Graphics.TextBox.commands(
        "A long paragraph that should wrap automatically.",
        x: 72,
        y: 700,
        width: 400,
        height: 120,
        font: :helvetica,
        resource_name: "F1",
        size: 12,
        line_height: 16,
        align: :left
      )
  """
  @spec commands(binary(), keyword()) :: result()
  def commands(text, options)
      when is_binary(text) and is_list(options) do
    validate_options!(options)

    width =
      Keyword.fetch!(options, :width)

    size =
      Keyword.get(
        options,
        :size,
        @default_size
      )

    line_height =
      Keyword.get(
        options,
        :line_height,
        size * 1.2
      )

    height =
      Keyword.get(
        options,
        :height
      )

    lines =
      TextWrapper.wrap(
        text,
        width: width,
        font: Keyword.fetch!(options, :font),
        font_instance: Keyword.get(options, :font_instance),
        size: size
      )

    {visible_lines, remaining_lines} = split_visible_lines(lines, height, line_height)
    overflow = Keyword.get(options, :overflow, :clip)
    visible_lines = apply_overflow(visible_lines, remaining_lines, overflow, options)

    commands =
      build_commands(
        visible_lines,
        options,
        line_height
      )

    %{
      commands: commands,
      lines: visible_lines,
      remaining_lines: remaining_lines,
      overflow?: remaining_lines != [],
      consumed_height: length(visible_lines) * line_height
    }
  end

  defp build_commands(
         lines,
         options,
         line_height
       ) do
    start_y =
      Keyword.fetch!(
        options,
        :y
      )

    last_index = length(lines) - 1

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      line_y =
        start_y - index * line_height

      line_options =
        options
        |> Keyword.put(:y, line_y)
        |> maybe_disable_last_justification(index == last_index)
        |> Keyword.delete(:height)
        |> Keyword.delete(:line_height)
        |> Keyword.delete(:overflow)

      Text.command(
        line,
        line_options
      )
    end)
    |> Enum.intersperse("\n")
  end

  defp split_visible_lines(
         lines,
         nil,
         _line_height
       ) do
    {lines, []}
  end

  defp split_visible_lines(
         lines,
         height,
         line_height
       ) do
    maximum_lines =
      height
      |> Kernel./(line_height)
      |> floor()

    Enum.split(lines, maximum_lines)
  end

  defp apply_overflow(visible, [], _strategy, _options), do: visible
  defp apply_overflow(visible, _remaining, :clip, _options), do: visible
  defp apply_overflow(visible, _remaining, :continue, _options), do: visible

  defp apply_overflow([], _remaining, :ellipsis, _options), do: []

  defp apply_overflow(visible, _remaining, :ellipsis, options) do
    List.replace_at(visible, -1, ellipsize(List.last(visible), options))
  end

  defp apply_overflow(_visible, _remaining, :error, _options) do
    raise ArgumentError, "text does not fit inside the requested text box height"
  end

  defp apply_overflow(_visible, _remaining, strategy, _options) do
    raise ArgumentError,
          "text overflow must be :clip, :ellipsis, :continue, or :error, received: " <>
            inspect(strategy)
  end

  defp ellipsize(line, options) do
    width = Keyword.fetch!(options, :width)
    suffix = "..."

    line
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.reduce_while(line, fn _grapheme, current ->
      candidate = String.slice(current, 0, max(String.length(current) - 1, 0)) <> suffix

      if line_fits?(candidate, width, options),
        do: {:halt, candidate},
        else: {:cont, String.slice(current, 0, max(String.length(current) - 1, 0))}
    end)
  end

  defp line_fits?(line, width, options) do
    PaperForge.TextMetrics.line_width(line,
      font: Keyword.fetch!(options, :font),
      font_instance: Keyword.get(options, :font_instance),
      size: Keyword.get(options, :size, @default_size)
    ) <= width
  end

  defp maybe_disable_last_justification(options, true) do
    if Keyword.get(options, :align) == :justify,
      do: Keyword.put(options, :align, :left),
      else: options
  end

  defp maybe_disable_last_justification(options, false), do: options

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
      :width
    )

    validate_required_option!(
      options,
      :font
    )

    validate_required_option!(
      options,
      :resource_name
    )

    validate_positive_number!(
      :width,
      Keyword.fetch!(
        options,
        :width
      )
    )

    size =
      Keyword.get(
        options,
        :size,
        @default_size
      )

    validate_positive_number!(
      :size,
      size
    )

    line_height =
      Keyword.get(
        options,
        :line_height,
        size * 1.2
      )

    validate_positive_number!(
      :line_height,
      line_height
    )

    case Keyword.get(
           options,
           :height
         ) do
      nil ->
        :ok

      height ->
        validate_positive_number!(
          :height,
          height
        )
    end
  end

  defp validate_required_option!(
         options,
         option
       ) do
    unless Keyword.has_key?(
             options,
             option
           ) do
      raise ArgumentError,
            "missing required text box option #{inspect(option)}"
    end
  end

  defp validate_positive_number!(
         _name,
         value
       )
       when is_number(value) and value > 0 do
    :ok
  end

  defp validate_positive_number!(
         name,
         value
       ) do
    raise ArgumentError,
          "#{name} must be greater than zero, received: " <>
            inspect(value)
  end
end
