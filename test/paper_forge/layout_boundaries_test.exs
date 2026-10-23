defmodule PaperForge.LayoutBoundariesTest do
  use ExUnit.Case, async: true

  alias PaperForge.{Flow, Margins, Page}

  defp layout(fun) do
    PaperForge.layout(PaperForge.new(), fun, page_options: [size: {200, 200}, margins: 20])
  end

  test "fixed height blocks move before crossing the bottom margin" do
    for append <- [
          &Flow.spacer(&1, 20),
          &Flow.separator(&1, height: 20),
          &Flow.custom(&1, fn page, _ -> page end, height: 20)
        ] do
      {_, report} = layout(fn flow -> append.(Flow.spacer(flow, 150)) end)
      assert report.pages == 2
      assert List.last(report.placements).y == 20
    end
  end

  test "headings reserve all wrapped lines before the following paragraph" do
    {_, report} =
      layout(fn flow ->
        flow
        |> Flow.heading("A long heading that wraps over several lines", size: 20)
        |> Flow.paragraph("Following")
      end)

    [heading, following] = report.placements
    assert length(heading.lines) > 1
    assert following.y >= heading.y + length(heading.lines) * 27
  end

  test "default line height scales with the requested font size" do
    {_, report} = layout(&Flow.paragraph(&1, "One\nTwo", size: 30))
    assert hd(report.placements).height >= 81
  end

  test "pagination recalculates capacity after moving a padded paragraph" do
    lines = Enum.map_join(1..20, "\n", &"Line #{&1}")

    {_, report} =
      layout(fn flow ->
        flow |> Flow.spacer(120) |> Flow.paragraph(lines, size: 10, line_height: 12, padding: 10)
      end)

    assert report.pages == 3
    text = Enum.filter(report.placements, &(&1.type == :paragraph))
    assert Enum.flat_map(text, & &1.lines) == String.split(lines, "\n")
    assert Enum.all?(text, &(&1.y + &1.height <= 180))
    assert length(hd(text).lines) == 11
  end

  test "a nearly full page does not force a single line onto the next page" do
    lines = Enum.map_join(1..10, "\n", &"Line #{&1}")

    {_, report} =
      layout(fn flow ->
        flow |> Flow.spacer(150) |> Flow.paragraph(lines, line_height: 12, min_lines_at_top: 1)
      end)

    assert report.pages == 2
    assert length(List.last(report.placements).lines) == 10
  end

  test "keep together includes padding and paragraph spacing" do
    {_, report} =
      layout(fn flow ->
        flow
        |> Flow.spacer(80)
        |> Flow.keep_together(fn group ->
          Enum.reduce(1..3, group, fn n, acc ->
            Flow.paragraph(acc, "Paragraph #{n}", line_height: 10, padding: 10)
          end)
        end)
      end)

    text = Enum.filter(report.placements, &(&1.type == :paragraph))
    assert Enum.map(text, & &1.page_number) == [2, 2, 2]
  end

  test "margin structs are validated like keyword margins" do
    assert_raise ArgumentError, fn -> Page.new(margins: %Margins{left: -1}) end
    assert_raise ArgumentError, fn -> Margins.new(%Margins{top: "20"}) end
  end
end
