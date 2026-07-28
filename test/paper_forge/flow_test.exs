defmodule PaperForge.FlowTest do
  use ExUnit.Case, async: true

  alias PaperForge.Document
  alias PaperForge.Flow
  alias PaperForge.Layout.Block
  alias PaperForge.LayoutError
  alias PaperForge.NavigationError
  alias PaperForge.Page
  alias PaperForge.PageTemplateError

  @font_path "test/fixtures/fonts/SFNSMono.ttf"
  @png_path "assets/rgba_1000.png"

  test "builds stable block identifiers" do
    first = Block.new(:paragraph, "Hello", [])
    second = Block.new(:paragraph, "Hello", [])

    assert first.id == second.id
    assert first.type == :paragraph
  end

  test "builds a unified flow with headings paragraphs and lists" do
    flow =
      Flow.new()
      |> Flow.heading("Report", level: 1)
      |> Flow.paragraph("A paragraph")
      |> Flow.list(["One", "Two"], type: :ordered)

    assert length(flow.blocks) == 3
  end

  test "renders a unified flow with bookmarks and named heading destinations" do
    {document, report} =
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.heading("Quarterly report", id: "quarterly-report")
          |> Flow.paragraph(String.duplicate("A wrapped paragraph. ", 30))
          |> Flow.separator()
          |> Flow.spacer(16)
          |> Flow.list(["Revenue", "Expenses", "Cash"], type: :unordered)
        end,
        page_options: [size: {240, 260}, margins: 24],
        footer: "Page {page} of {total}"
      )

    assert report.pages >= 1
    assert report.blocks == 5

    catalog =
      document
      |> Document.fetch_object!(document.root_reference)
      |> Map.fetch!(:value)

    assert catalog["Names"]
    assert catalog["Outlines"]
    assert PaperForge.to_binary(document) =~ "/Outlines"
  end

  test "renders section blocks and page breaks" do
    {document, report} =
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.section(:intro, [title: "Intro", page_break_before: true], fn section ->
            section
            |> Flow.paragraph("Intro body")
          end)
          |> Flow.page_break()
          |> Flow.heading("Next")
        end,
        page_options: [size: {260, 260}, margins: 24]
      )

    pages =
      document
      |> Document.fetch_object!(document.pages_reference)
      |> Map.fetch!(:value)

    assert report.pages == pages["Count"]
    assert pages["Count"] >= 2
  end

  test "honors page break after block options" do
    {_document, report} =
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.heading("First page", page_break_after: true)
          |> Flow.paragraph("Second page")
        end,
        page_options: [size: {260, 260}, margins: 24]
      )

    assert report.pages == 2
  end

  test "raises a structured layout error for blocks that never fit" do
    assert_raise LayoutError, ~r/is too large/, fn ->
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          Flow.spacer(flow, 400)
        end,
        page_options: [size: {200, 220}, margins: 40]
      )
    end
  end

  test "raises for duplicate automatic heading destinations" do
    assert_raise NavigationError, ~r/duplicate destination/, fn ->
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.heading("Repeated")
          |> Flow.heading("Repeated")
        end,
        page_options: [size: {260, 260}, margins: 24]
      )
    end
  end

  test "raises for unresolved internal link targets declared on flow blocks" do
    assert_raise NavigationError, ~r/unresolved destination/, fn ->
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          Flow.paragraph(flow, "Jump", link_to: :missing)
        end,
        page_options: [size: {260, 260}, margins: 24]
      )
    end
  end

  test "uses page templates with page total placeholders" do
    {document, report} =
      PaperForge.new()
      |> PaperForge.page_template(
        :report,
        size: {240, 260},
        margins: 24,
        header: fn page, context ->
          Page.text(page, "Header #{context.page_number}/#{context.total_pages}",
            x: context.content_left,
            y: 8,
            width: context.content_width,
            align: :center,
            size: 8
          )
        end,
        footer: "Page {page} of {total}"
      )
      |> PaperForge.layout(
        fn flow ->
          Enum.reduce(1..30, flow, fn index, current ->
            Flow.paragraph(current, "Paragraph #{index}: " <> String.duplicate("text ", 12))
          end)
        end,
        template: :report
      )

    assert report.pages > 1
    assert PaperForge.to_binary(document) =~ "/FlateDecode"
  end

  test "sections can switch page templates and report placement dimensions" do
    {document, report} =
      PaperForge.new(compress: false)
      |> PaperForge.page_template(
        :appendix,
        margins: [top: 50, right: 30, bottom: 40, left: 30],
        footer: "Appendix {page}/{total}"
      )
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.paragraph("Main body")
          |> Flow.section(:appendix, [title: "Appendix", template: :appendix], fn section ->
            Flow.paragraph(section, "Appendix body")
          end)
        end,
        page_options: [size: {260, 260}, margins: 24]
      )

    appendix_placement =
      Enum.find(report.placements, fn placement ->
        placement.type == :heading and placement.section == :appendix
      end)

    assert appendix_placement.x == 30
    assert appendix_placement.width == 200
    assert appendix_placement.height > 0
    assert PaperForge.to_binary(document) =~ "Appendix"
  end

  test "raises for missing page templates" do
    assert_raise PageTemplateError, ~r/unknown page template/, fn ->
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          Flow.paragraph(flow, "Hello")
        end,
        template: :missing
      )
    end
  end

  test "renders tables and images as flow blocks" do
    {document, report} =
      PaperForge.new()
      |> PaperForge.register_font(:sfmono, path: @font_path)
      |> PaperForge.default_font(:sfmono)
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.heading("Assets")
          |> Flow.table(
            ["Name", "Value"],
            [
              ["Rows", 2],
              ["Mode", "flow"]
            ],
            repeat_header: true,
            font: :sfmono,
            size: 8
          )
          |> Flow.image(@png_path, width: 80, height: 80, align: :center, caption: "PNG alpha")
        end,
        page_options: [size: :a4, margins: 72]
      )

    assert report.pages == 1
    pdf = PaperForge.to_binary(document)
    assert pdf =~ "/SMask"
    assert pdf =~ "/ToUnicode"
  end

  test "debug returns a structured document report" do
    document =
      PaperForge.new()
      |> PaperForge.flow(fn flow ->
        Flow.paragraph(flow, "Debug me")
      end)

    report =
      PaperForge.debug(document,
        show_margins: true,
        show_blocks: true,
        show_page_breaks: true
      )

    assert report.pages == 1
    assert report.objects > 0
    assert report.show_margins
    assert report.show_blocks
    assert report.show_page_breaks
  end
end
