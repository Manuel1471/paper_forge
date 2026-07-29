defmodule PaperForge.Graphics.TextBoxTest do
  use ExUnit.Case, async: true

  alias PaperForge.Graphics.TextBox

  test "wraps text automatically" do
    result =
      TextBox.commands(
        "PaperForge wraps text into lines",
        base_options(width: 80)
      )

    assert length(result.lines) > 1
    refute result.overflow?
  end

  test "splits words that are too long for the width" do
    result =
      TextBox.commands(
        "supercalifragilistic",
        base_options(width: 20)
      )

    assert length(result.lines) > 1
    assert Enum.join(result.lines) == "supercalifragilistic"
  end

  test "preserves explicit line breaks" do
    result =
      TextBox.commands(
        "first\nsecond",
        base_options(width: 200)
      )

    assert result.lines == [
             "first",
             "second"
           ]
  end

  test "supports left, center, and right alignment" do
    left =
      TextBox.commands(
        "Align",
        base_options(align: :left)
      ).commands
      |> IO.iodata_to_binary()

    center =
      TextBox.commands(
        "Align",
        base_options(align: :center)
      ).commands
      |> IO.iodata_to_binary()

    right =
      TextBox.commands(
        "Align",
        base_options(align: :right)
      ).commands
      |> IO.iodata_to_binary()

    assert left =~ "1 0 0 1 10 100 Tm"
    refute center == left
    refute right == left
  end

  test "respects height limits and reports overflow" do
    result =
      TextBox.commands(
        "one two three four five six",
        base_options(width: 35, height: 20, line_height: 10)
      )

    assert length(result.lines) == 2
    assert result.consumed_height == 20
    assert result.overflow?
    assert result.remaining_lines != []
  end

  test "supports ellipsis, continuation, error, and justified text" do
    ellipsis =
      TextBox.commands(
        "one two three four five six",
        base_options(width: 35, height: 10, line_height: 10, overflow: :ellipsis)
      )

    assert List.last(ellipsis.lines) =~ "..."

    continuation =
      TextBox.commands(
        "one two three four five six",
        base_options(width: 35, height: 10, line_height: 10, overflow: :continue)
      )

    assert continuation.remaining_lines != []

    assert_raise ArgumentError, ~r/does not fit/, fn ->
      TextBox.commands(
        "one two three four five six",
        base_options(width: 35, height: 10, line_height: 10, overflow: :error)
      )
    end

    justified =
      TextBox.commands(
        "one two three four",
        base_options(width: 55, align: :justify)
      ).commands
      |> IO.iodata_to_binary()

    assert justified =~ " Tw"
  end

  test "handles empty text" do
    result =
      TextBox.commands(
        "",
        base_options()
      )

    assert result.lines == [""]
    assert result.consumed_height == 12
    refute result.overflow?
  end

  defp base_options(overrides \\ []) do
    Keyword.merge(
      [
        x: 10,
        y: 100,
        width: 100,
        font: :helvetica,
        resource_name: "F1",
        size: 10,
        line_height: 12
      ],
      overrides
    )
  end
end
