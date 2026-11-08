defmodule PaperForge.TableStyleTest do
  use ExUnit.Case, async: true

  alias PaperForge.Color
  alias PaperForge.Flow
  alias PaperForge.Page

  test "axis padding and header typography preserve legacy output when values match" do
    rows = [["Header"], ["Body"]]

    legacy =
      Page.new(origin: :top_left)
      |> Page.table(rows,
        x: 24,
        y: 24,
        width: 120,
        row_height: 24,
        padding: 6,
        font: :helvetica,
        size: 10,
        line_height: 13,
        header: true
      )
      |> Page.content()

    styled =
      Page.new(origin: :top_left)
      |> Page.table(rows,
        x: 24,
        y: 24,
        width: 120,
        row_height: 24,
        padding: 6,
        padding_x: 6,
        padding_y: 6,
        font: :helvetica,
        size: 10,
        line_height: 13,
        header_font: :helvetica,
        header_size: 10,
        header_line_height: 13,
        header: true
      )
      |> Page.content()

    assert styled == legacy
  end

  test "header typography, axis padding, and cell border colors reach page operations" do
    header_rule = Color.rgb255(24, 24, 27)
    body_rule = Color.rgb255(228, 228, 231)

    {_, report} =
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          Flow.table(
            flow,
            [Flow.cell("Header", borders: [:bottom], border_color: header_rule)],
            [[Flow.cell("Body", borders: [:bottom], border_color: body_rule)]],
            repeat_header: true,
            row_height: 0,
            padding: 4.5,
            padding_x: 6,
            padding_y: 4.5,
            font: :helvetica,
            size: 9.75,
            cell_line_height: 14.1375,
            header_font: :helvetica_bold,
            header_size: 9,
            header_line_height: 12.15,
            borders: :none
          )
        end,
        page_options: [size: {240, 180}, margins: 24]
      )

    [placement] = report.placements
    assert Enum.map(placement.rows, & &1.height) == [21.15, 23.1375]

    operations = hd(report.rendered_pages).operations

    assert {:text_box, "Header", header_options} =
             Enum.find(operations, &match?({:text_box, "Header", _}, &1))

    assert header_options[:font] == :helvetica_bold
    assert header_options[:size] == 9
    assert header_options[:line_height] == 12.15
    assert header_options[:x] == 30

    assert {:rectangle, rectangle_options} =
             Enum.find(operations, &match?({:rectangle, _}, &1))

    assert header_options[:width] == rectangle_options[:width] - 12

    assert {:text_box, "Body", body_options} =
             Enum.find(operations, &match?({:text_box, "Body", _}, &1))

    assert body_options[:font] == :helvetica
    assert body_options[:size] == 9.75
    assert body_options[:line_height] == 14.1375
    assert body_options[:x] == 30
    assert body_options[:width] == rectangle_options[:width] - 12

    line_colors =
      for {:line, options} <- operations, do: options[:color]

    assert header_rule in line_colors
    assert body_rule in line_colors
  end

  test "styled headers repeat while wrapped long tables paginate natively" do
    rows =
      for index <- 1..30 do
        ["Row #{index}", String.duplicate("wrapped content ", 8)]
      end

    {_, report} =
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          Flow.table(flow, ["Name", "Description"], rows,
            repeat_header: true,
            row_split: :split,
            column_widths: [48, 144],
            row_height: 0,
            padding_x: 6,
            padding_y: 4.5,
            font: :helvetica,
            size: 9.75,
            cell_line_height: 14.1375,
            header_font: :helvetica_bold,
            header_size: 9,
            header_line_height: 12.15
          )
        end,
        page_options: [size: {240, 180}, margins: 24]
      )

    assert report.pages > 2

    for page <- report.rendered_pages do
      assert {:text_box, "Name", options} =
               Enum.find(page.operations, &match?({:text_box, "Name", _}, &1))

      assert options[:font] == :helvetica_bold
      assert options[:size] == 9
      assert options[:line_height] == 12.15
    end

    rendered_text =
      for page <- report.rendered_pages,
          {:text_box, text, _options} <- page.operations,
          do: text

    assert Enum.any?(rendered_text, &String.contains?(&1, "wrapped"))
    assert Enum.any?(rendered_text, &String.contains?(&1, "Row 30"))
  end

  test "header styles stay on the header when later pages do not repeat it" do
    rows = for index <- 1..12, do: ["Row #{index}"]

    {_, report} =
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          Flow.table(flow, ["Name"], rows,
            repeat_header: false,
            row_height: 20,
            padding_y: 4.5,
            font: :helvetica,
            size: 9.75,
            cell_line_height: 14.1375,
            header_font: :helvetica_bold,
            header_size: 9,
            header_line_height: 12.15
          )
        end,
        page_options: [size: {240, 120}, margins: 24]
      )

    assert report.pages > 1
    [first | rest] = report.rendered_pages

    assert {:text_box, "Name", header_options} =
             Enum.find(first.operations, &match?({:text_box, "Name", _}, &1))

    assert header_options[:font] == :helvetica_bold
    assert header_options[:size] == 9

    for page <- rest do
      refute Enum.any?(page.operations, &match?({:text_box, "Name", _}, &1))

      assert {:text_box, "Row " <> _, options} =
               Enum.find(page.operations, &match?({:text_box, "Row " <> _, _}, &1))

      assert options[:font] == :helvetica
      assert options[:size] == 9.75
      assert options[:line_height] == 14.1375
    end
  end
end
