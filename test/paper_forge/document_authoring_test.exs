defmodule PaperForge.DocumentAuthoringTest do
  use ExUnit.Case, async: true

  alias PaperForge.Document
  alias PaperForge.Flow

  test "resolves inherited page templates and rejects inheritance cycles" do
    document =
      PaperForge.new()
      |> PaperForge.page_template(:base, size: {280, 320}, margins: 28, footer: "Page {page}")
      |> PaperForge.page_template(:report, extends: :base, header: "Report")

    assert {:ok, options} = Document.resolve_page_template(document, :report)
    assert options[:size] == {280, 320}
    assert options[:header] == "Report"

    cyclic =
      document
      |> PaperForge.page_template(:a, extends: :b)
      |> PaperForge.page_template(:b, extends: :a)

    assert {:error, :cycle} = Document.resolve_page_template(cyclic, :a)
  end

  test "renders styles components a table of contents grids and columns" do
    document =
      PaperForge.new(compress: false)
      |> PaperForge.style(:heading, size: 18, color: PaperForge.Color.rgb255(24, 78, 119))
      |> PaperForge.style(:body,
        size: 9,
        line_height: 12,
        color: PaperForge.Color.rgb255(48, 52, 63)
      )
      |> PaperForge.component(:metric_card, fn assigns ->
        Flow.new()
        |> Flow.rich_text([
          {assigns.label, [size: 8, color: PaperForge.Color.gray(0.38)]},
          {"  #{assigns.value}", [size: 16, weight: :bold]}
        ])
      end)
      |> PaperForge.page_template(:base,
        size: {300, 380},
        margins: 30,
        footer: "Page {page} of {total}"
      )
      |> PaperForge.page_template(:report, extends: :base, header: "Northstar Analytics")

    {document, report} =
      PaperForge.layout(
        document,
        fn flow ->
          flow
          |> Flow.table_of_contents(title: "Report contents")
          |> Flow.heading("Executive summary", destination: :summary)
          |> Flow.paragraph("A styled paragraph for a document authoring integration test.",
            style: :body
          )
          |> Flow.grid(2, ["Revenue", "Retention", "Pipeline", "Coverage"], cell_height: 52)
          |> Flow.component(:metric_card, %{label: "Net revenue", value: "$1.24M"})
          |> Flow.heading("Narrative")
          |> Flow.columns(2, [
            "The layout engine keeps document authoring declarative and predictable.",
            "Columns are useful for reports, statements, and editorial summaries.",
            "Templates carry shared page geometry and late page context.",
            "Components turn repeated document fragments into small, testable units."
          ])
          |> Flow.table(["Metric", "Value"], [["Revenue", "$1.24M"], ["Margin", "31%"]],
            column_widths: [150, 90],
            stripe_fill_color: PaperForge.Color.gray(0.96)
          )
        end,
        template: :report
      )

    assert report.pages >= 1
    assert Enum.any?(report.placements, &(&1.type == :grid))
    assert Enum.any?(report.placements, &(&1.type == :columns))
    pdf = PaperForge.to_binary(document)
    assert pdf =~ "Northstar Analytics"
    assert pdf =~ "Report contents"
  end

  test "renders chart and SVG vector flow blocks with measurement diagnostics" do
    {document, report} =
      PaperForge.new(compress: false)
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.paragraph("Antidisestablishmentarianism", width: 80, hyphenate: true)
          |> Flow.chart([{"Q1", 12}, {"Q2", 18}, {"Q3", 15}], height: 80)
          |> Flow.svg(
            "<svg><rect x='0' y='0' width='40' height='20' fill='#0077b5'/><circle cx='60' cy='10' r='8' fill='#44aa88'/></svg>",
            height: 40
          )
          |> Flow.qr_code("https://hex.pm/packages/paper_forge", width: 72, height: 72)
          |> Flow.barcode("20481234", width: 120, height: 54)
        end,
        page_options: [size: {300, 320}, margins: 30]
      )

    assert Enum.any?(report.placements, &(&1.type == :chart))
    assert Enum.any?(report.placements, &(&1.type == :svg))
    assert Enum.any?(report.placements, &(&1.type == :qr_code))
    assert Enum.any?(report.placements, &(&1.type == :barcode))
    assert length(report.measurements) == length(report.placements)
    assert PaperForge.to_binary(document) =~ " re"
  end

  test "renders SVG paths, transforms, viewBox, groups, clipping, and cascading styles" do
    svg = """
    <svg viewBox="0 0 100 50">
      <defs>
        <clipPath id="window"><rect x="5" y="5" width="90" height="40"/></clipPath>
      </defs>
      <g transform="translate(5 0)" style="fill:#00887a;stroke:#17343f;stroke-width:2">
        <path clip-path="url(#window)" d="M 0 40 L 20 10 Q 35 0 50 10 C 65 20 80 20 95 5 Z"/>
        <polygon points="10,45 20,30 30,45"/>
      </g>
    </svg>
    """

    page =
      PaperForge.Page.new(size: {240, 180}, origin: :top_left)
      |> PaperForge.SVG.render(svg, x: 20, y: 20, width: 180, height: 90)

    content = PaperForge.PageCompiler.compile_content(page)

    assert content =~ " c\n"
    assert content =~ "W n"
    assert content =~ "0 0.533333 0.478431 rg"
    assert content =~ "0.090196 0.203922 0.247059 RG"
  end

  test "reserves space above the tallest chart bar for its value label" do
    {document, _report} =
      PaperForge.new(compress: false)
      |> PaperForge.layout(
        fn flow ->
          Flow.chart(flow, [{"Q1", 12}, {"Q2", 18}], height: 80)
        end,
        page_options: [size: {300, 320}, margins: 30]
      )

    pdf = PaperForge.to_binary(document)

    [_, bar_y, bar_height] =
      Regex.run(~r/156 ([\d.]+) 114 ([\d.]+) re/, pdf)

    [_, label_y] =
      Regex.run(~r/1 0 0 1 [\d.]+ ([\d.]+) Tm\n\(18\)/, pdf)

    parse_number = fn value ->
      {number, ""} = Float.parse(value)
      number
    end

    assert parse_number.(label_y) > parse_number.(bar_y) + parse_number.(bar_height)
  end

  test "selects first, odd, even, and last page template variants" do
    {document, report} =
      PaperForge.new(compress: false)
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.paragraph("One")
          |> Flow.page_break()
          |> Flow.paragraph("Two")
          |> Flow.page_break()
          |> Flow.paragraph("Three")
          |> Flow.page_break()
          |> Flow.paragraph("Four")
        end,
        page_options: [size: {240, 240}, margins: 30],
        header: "Default",
        first_header: "First {page}/{total}",
        odd_header: "Odd {page}",
        even_header: "Even {page}",
        last_header: "Last {page}/{total}",
        footer: "Section {section_page}/{section_total}"
      )

    assert report.pages == 4
    pdf = PaperForge.to_binary(document)
    assert pdf =~ "First 1/4"
    assert pdf =~ "Even 2"
    assert pdf =~ "Odd 3"
    assert pdf =~ "Last 4/4"
    assert pdf =~ "Section 4/4"
    refute pdf =~ "(Default)"
  end

  test "renders composable table cells with spans, nested blocks, alignment, and borders" do
    nested =
      PaperForge.Layout.Block.new(:paragraph, "Nested cell content", size: 8)

    {document, report} =
      PaperForge.new(compress: false)
      |> PaperForge.layout(
        fn flow ->
          Flow.table(
            flow,
            ["Area", "Metric", "Status"],
            [
              [
                Flow.cell("Operations", rowspan: 2, valign: :middle, borders: [:left, :top]),
                Flow.cell("Availability"),
                Flow.cell("96%", align: :right)
              ],
              [
                Flow.cell([nested], colspan: 2, fill_color: PaperForge.Color.gray(0.95))
              ]
            ],
            column_widths: [90, 100, 70],
            row_split: :split
          )
        end,
        page_options: [size: {320, 260}, margins: 30]
      )

    assert Enum.any?(report.placements, &(&1.type == :table))
    pdf = PaperForge.to_binary(document)
    assert pdf =~ "Operations"
    assert pdf =~ "Nested cell content"
  end

  test "keeps rowspan groups intact across multipage table boundaries" do
    leading_rows =
      for index <- 1..5 do
        ["Row #{index}", "Leading content"]
      end

    spanning_rows = [
      [Flow.cell("Spanning", rowspan: 2, valign: :middle), "First half"],
      ["Second half"]
    ]

    {_document, report} =
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          Flow.table(flow, ["Group", "Description"], leading_rows ++ spanning_rows,
            column_widths: [90, 130],
            row_height: 32,
            row_split: :split,
            repeat_header: true
          )
        end,
        page_options: [size: {280, 240}, margins: 30]
      )

    table_parts = Enum.filter(report.placements, &(&1.type == :table))

    spanning_part =
      Enum.find(table_parts, fn placement ->
        Enum.any?(placement.rows, fn row ->
          Enum.any?(row.cells, fn cell -> "Spanning" in cell.lines end)
        end)
      end)

    assert Enum.any?(spanning_part.rows, fn row ->
             Enum.any?(row.cells, fn cell -> "Second half" in cell.lines end)
           end)
  end

  test "numbers table captions and resolves page-aware document references" do
    {document, report} =
      PaperForge.new(compress: false)
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.table(["Metric", "Value"], [["Revenue", "$42M"]],
            numbered: true,
            caption: "Operating summary"
          )
          |> Flow.page_break()
          |> Flow.reference("table-1", text: "Return to Table 1, page {page}")
        end,
        page_options: [size: {300, 260}, margins: 30]
      )

    assert report.pages == 2
    pdf = PaperForge.to_binary(document)
    assert pdf =~ "Table 1. Operating summary"
    assert pdf =~ "Return to Table 1, page 1"
    assert pdf =~ "/Subtype /Link"
  end

  test "customizes multilevel table of contents entries" do
    {document, _report} =
      PaperForge.new(compress: false)
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.table_of_contents(
            levels: 1..2,
            leader: "-",
            indent: 8,
            level_styles: %{2 => [size: 8]},
            entry_formatter: fn entry ->
              "#{entry.level}: #{entry.title} -> #{entry.page}"
            end
          )
          |> Flow.page_break()
          |> Flow.heading("Overview", level: 1)
          |> Flow.heading("Details", level: 2)
          |> Flow.heading("Hidden", level: 3)
        end,
        page_options: [size: {300, 320}, margins: 30]
      )

    pdf = PaperForge.to_binary(document)
    assert pdf =~ "1: Overview -> 2"
    assert pdf =~ "2: Details -> 2"
    refute pdf =~ "3: Hidden ->"
  end

  test "embeds attachments and emits text-note and highlight annotations" do
    document =
      PaperForge.new(compress: false)
      |> PaperForge.attach("source.csv", "name,value\nrevenue,486", mime: "text/csv")
      |> PaperForge.add_page([size: {240, 240}, origin: :top_left, margins: 20], fn page ->
        page
        |> PaperForge.Page.text("Reviewed earnings", x: 20, y: 40)
        |> PaperForge.Page.note("Board review", x: 190, y: 30)
        |> PaperForge.Page.highlight("Verified", x: 20, y: 28, width: 110, height: 18)
      end)

    pdf = PaperForge.to_binary(document)
    assert pdf =~ "/EmbeddedFile"
    assert pdf =~ "/EmbeddedFiles"
    assert pdf =~ "/Subtype /Text"
    assert pdf =~ "/Subtype /Highlight"
  end

  test "builds page-reserved footnotes and automatic endnotes" do
    flow =
      Flow.new()
      |> Flow.paragraph("Statement with notes")
      |> Flow.footnote(1, "Unaudited management estimate.")
      |> Flow.endnotes([{2, "Comparable-period values were restated."}])

    assert Enum.any?(flow.blocks, &(&1.type == :footnote))
    assert Enum.any?(flow.blocks, &(&1.type == :endnotes))

    assert Enum.any?(flow.blocks, fn
             %{type: :paragraph, content: content} -> String.ends_with?(content, "[1]")
             _block -> false
           end)

    {_document, report} = PaperForge.layout(PaperForge.new(), fn _ -> flow end)
    footnote = Enum.find(report.placements, &(&1.type == :footnote))
    assert footnote.y > 700
    assert footnote.y - footnote.separator_y >= 12
  end

  test "table of contents and references resolve stable page numbers" do
    {document, report} =
      PaperForge.layout(PaperForge.new(compress: false), fn flow ->
        flow
        |> Flow.table_of_contents(title: "Contents")
        |> Flow.page_break()
        |> Flow.heading("Results", destination: :results)
        |> Flow.paragraph("The result is page-aware.")
        |> Flow.reference(:results, prefix: "Results are on page ")
      end)

    assert report.pages == 2
    pdf = PaperForge.to_binary(document)
    assert pdf =~ "Results are on page 2"
    assert pdf =~ "Results "
    assert pdf =~ "/Subtype /Link"
    assert pdf =~ "/Dest (results)"
  end

  test "custom blocks receive their measured placement" do
    parent = self()

    PaperForge.layout(PaperForge.new(), fn flow ->
      Flow.custom(
        flow,
        fn page, context ->
          send(parent, {:placement, context.block_x, context.block_y, context.block_height})
          page
        end,
        height: 42,
        width: 180
      )
    end)

    assert_receive {:placement, x, y, 42}
    assert is_number(x)
    assert is_number(y)
  end

  test "tables wrap cells and derive row height from content" do
    {_document, report} =
      PaperForge.layout(
        PaperForge.new(),
        fn flow ->
          Flow.table(
            flow,
            ["Item", "Description"],
            [["A", String.duplicate("wrapped content ", 8)]],
            column_widths: [45, 115],
            row_height: 20,
            size: 9
          )
        end,
        page_options: [size: {220, 260}, margins: 30]
      )

    table = Enum.find(report.placements, &(&1.type == :table))
    assert table.height > 40
  end

  test "row_split split continues a tall cell and repeats its header" do
    {_document, report} =
      PaperForge.layout(
        PaperForge.new(),
        fn flow ->
          Flow.table(
            flow,
            ["Item", "Description"],
            [["A", String.duplicate("continuation content ", 90)]],
            column_widths: [45, 115],
            row_split: :split,
            row_height: 20,
            size: 9
          )
        end,
        page_options: [size: {220, 220}, margins: 24]
      )

    tables = Enum.filter(report.placements, &(&1.type == :table))
    assert length(tables) > 1
    assert report.pages == length(tables)
  end

  test "row_split error rejects a row taller than an empty page" do
    assert_raise PaperForge.TableError, fn ->
      PaperForge.layout(
        PaperForge.new(),
        fn flow ->
          Flow.table(
            flow,
            ["Description"],
            [[String.duplicate("oversized content ", 80)]],
            column_widths: [150],
            row_split: :error
          )
        end,
        page_options: [size: {210, 180}, margins: 24]
      )
    end
  end
end
