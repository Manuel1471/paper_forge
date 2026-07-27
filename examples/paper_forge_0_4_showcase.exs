alias PaperForge.Color
alias PaperForge.Fonts.TrueType
alias PaperForge.Fonts.TrueType.Subsetter
alias PaperForge.Page

root_dir =
  Path.expand("..", __DIR__)

output_path =
  Path.join(root_dir, "tmp/paper_forge_0_4_showcase.pdf")

font_path =
  Path.join(root_dir, "test/fixtures/fonts/SFNSMono.ttf")

font_data =
  File.read!(font_path)

font =
  TrueType.parse!(font_data)

{:ok, glyph_p} =
  TrueType.glyph_id(font, ?P)

{:ok, glyph_f} =
  TrueType.glyph_id(font, ?F)

subset_plan =
  Subsetter.plan(font, [glyph_p, glyph_f])

table_rows =
  [["Section", "Capability", "Status"]] ++
    for index <- 1..34 do
      [
        "0.4.0",
        "Paginated table row #{index}",
        "header repeats"
      ]
    end

flow_blocks =
  for index <- 1..36 do
    "Flow block #{index}: keep-together layout, headers, footers, overflow reporting, and Unicode text: Información — Ω — Привет."
  end

File.mkdir_p!(Path.dirname(output_path))

document =
  PaperForge.new(
    compress: true,
    pdf_version: "1.7",
    default_font: :sfmono_regular
  )
  |> PaperForge.register_font_family(
    :sfmono,
    regular: [data: font_data],
    bold: [data: font_data],
    italic: [data: font_data],
    bold_italic: [data: font_data]
  )
  |> PaperForge.default_font(:sfmono_regular)
  |> PaperForge.metadata(
    title: "PaperForge 0.4.0 Showcase",
    author: "Manuel Garcia",
    subject: "Advanced layout, PDF navigation, and TrueType subsetting foundation",
    keywords: [
      "PaperForge",
      "0.4.0",
      "TrueType",
      "subsetting",
      "bookmarks",
      "layout"
    ],
    creator: "PaperForge 0.4.0 example",
    producer: "PaperForge",
    creation_date: DateTime.utc_now(),
    modification_date: DateTime.utc_now()
  )
  |> PaperForge.add_page(
    [
      size: :a4,
      origin: :top_left,
      margins: 64
    ],
    fn page ->
      width = Page.content_width(page)
      left = Page.content_left(page)

      page
      |> Page.destination(:cover, y: 64)
      |> Page.bookmark("0.4.0 Cover", y: 64)
      |> Page.text(
        "PaperForge 0.4.0",
        y: 68,
        width: width,
        align: :center,
        font: :sfmono,
        weight: :bold,
        size: 26,
        color: Color.rgb255(28, 58, 110)
      )
      |> Page.text(
        "Advanced layout + PDF navigation + TrueType subsetting foundation",
        y: 106,
        width: width,
        align: :center,
        font: :sfmono,
        style: :italic,
        size: 10,
        color: Color.rgb255(80, 80, 80)
      )
      |> Page.line(
        x1: left,
        y1: 132,
        x2: left + width,
        y2: 132,
        width: 1,
        color: Color.rgb255(45, 90, 160)
      )
      |> Page.paragraph(
        """
        This example focuses on the 0.4.0 work: named destinations, internal
        links, outlines/bookmarks, ordered and unordered lists, paginated tables
        with repeated headers, flow reports, page headers/footers, and the new
        TrueType subsetting planner.
        """,
        y: 158,
        width: width,
        font: :sfmono,
        size: 10,
        line_height: 15
      )
      |> Page.list(
        [
          "Named destination on the cover page",
          "Outline bookmark pointing here",
          "Internal links to later sections",
          "TrueType font programs deduplicated by binary hash"
        ],
        x: left,
        y: 258,
        width: width,
        type: :ordered,
        font: :sfmono,
        size: 10,
        line_height: 18
      )
      |> Page.rectangle(
        x: left,
        y: 372,
        width: width,
        height: 118,
        fill: true,
        stroke: true,
        fill_color: Color.rgb255(239, 243, 248),
        stroke_color: Color.rgb255(120, 145, 180),
        line_width: 1
      )
      |> Page.text(
        "Jump to paginated table",
        x: left + 18,
        y: 410,
        font: :sfmono,
        weight: :bold,
        size: 12,
        color: Color.rgb255(24, 88, 170)
      )
      |> Page.link_to(
        :table_section,
        x: left + 18,
        y: 388,
        width: 190,
        height: 28
      )
      |> Page.text(
        "Jump to flow report",
        x: left + 18,
        y: 454,
        font: :sfmono,
        weight: :bold,
        size: 12,
        color: Color.rgb255(24, 88, 170)
      )
      |> Page.link_to(
        :flow_section,
        x: left + 18,
        y: 432,
        width: 160,
        height: 28
      )
      |> Page.table(
        [
          ["Subset plan field", "Example value"],
          ["Binary hash", String.slice(subset_plan.binary_hash, 0, 18) <> "..."],
          ["Requested glyphs", inspect(subset_plan.requested_glyphs)],
          ["Glyphs after dependencies", inspect(subset_plan.glyphs)],
          ["Tables to rebuild", Enum.join(subset_plan.rebuild_tables, ", ")]
        ],
        x: left,
        y: 540,
        width: width,
        font: :sfmono,
        size: 8,
        row_height: 27,
        header: true
      )
    end
  )
  |> PaperForge.add_page(
    [
      size: :a4,
      origin: :top_left,
      margins: 64
    ],
    fn page ->
      width = Page.content_width(page)
      left = Page.content_left(page)

      page
      |> Page.destination(:navigation_section, y: 64)
      |> Page.bookmark("Navigation", y: 64)
      |> Page.text(
        "PDF Navigation",
        y: 68,
        width: width,
        align: :center,
        font: :sfmono,
        weight: :bold,
        size: 22,
        color: Color.rgb255(28, 58, 110)
      )
      |> Page.paragraph(
        "This page demonstrates named destinations, internal links, URI links, and outlines/bookmarks.",
        y: 116,
        width: width,
        font: :sfmono,
        size: 10,
        line_height: 15
      )
      |> Page.list(
        [
          "Open the side panel in a PDF viewer to inspect bookmarks.",
          "Click internal links on the cover page.",
          "Click the external repository link below."
        ],
        x: left,
        y: 178,
        width: width,
        type: :unordered,
        font: :sfmono,
        size: 10,
        line_height: 18
      )
      |> Page.text(
        "External project link",
        x: left,
        y: 282,
        font: :sfmono,
        weight: :bold,
        size: 12,
        color: Color.rgb255(24, 88, 170)
      )
      |> Page.link(
        "https://github.com/Manuel1471/paper_forge",
        x: left,
        y: 260,
        width: 180,
        height: 28
      )
      |> Page.text(
        "Back to cover",
        x: left,
        y: 332,
        font: :sfmono,
        weight: :bold,
        size: 12,
        color: Color.rgb255(24, 88, 170)
      )
      |> Page.link_to(
        :cover,
        x: left,
        y: 310,
        width: 120,
        height: 28
      )
    end
  )
  |> PaperForge.add_table(
    table_rows,
    [
      size: :a4,
      origin: :top_left,
      margins: 64
    ],
    repeat_header: true,
    header_rows: 1,
    row_split: :keep,
    font: :sfmono,
    size: 8,
    row_height: 24,
    padding: 6
  )

{document, flow_report} =
  PaperForge.layout_flow(
    document,
    flow_blocks,
    [
      size: :a4,
      origin: :top_left,
      margins: 64
    ],
    font: :sfmono,
    size: 9,
    line_height: 13,
    gap: 5,
    keep_together: true,
    header: "PaperForge 0.4.0 flow header",
    footer: "Flow pages include headers, footers, and overflow reporting"
  )

document =
  PaperForge.add_page(
    document,
    [
      size: :a4,
      origin: :top_left,
      margins: 64
    ],
    fn page ->
      width = Page.content_width(page)
      left = Page.content_left(page)

      page
      |> Page.destination(:flow_section, y: 64)
      |> Page.bookmark("Flow Report", y: 64)
      |> Page.text(
        "Flow Report",
        y: 68,
        width: width,
        align: :center,
        font: :sfmono,
        weight: :bold,
        size: 22,
        color: Color.rgb255(28, 58, 110)
      )
      |> Page.table(
        [
          ["Metric", "Value"],
          ["Blocks", flow_report.blocks],
          ["Pages added", flow_report.pages_added],
          ["Overflow?", flow_report.overflow?],
          ["Keep together", true]
        ],
        x: left,
        y: 130,
        width: width,
        font: :sfmono,
        size: 9,
        row_height: 28,
        header: true
      )
      |> Page.text(
        "Back to cover",
        x: left,
        y: 320,
        font: :sfmono,
        weight: :bold,
        size: 12,
        color: Color.rgb255(24, 88, 170)
      )
      |> Page.link_to(
        :cover,
        x: left,
        y: 298,
        width: 120,
        height: 28
      )
    end
  )

document =
  PaperForge.add_page(
    document,
    [
      size: :a4,
      origin: :top_left,
      margins: 64
    ],
    fn page ->
      page
      |> Page.destination(:table_section, y: 64)
      |> Page.bookmark("Paginated Table", y: 64)
      |> Page.text(
        "The paginated table starts before this bookmark.",
        y: 68,
        width: Page.content_width(page),
        align: :center,
        font: :sfmono,
        size: 12
      )
      |> Page.text(
        "Back to cover",
        x: Page.content_left(page),
        y: 130,
        font: :sfmono,
        weight: :bold,
        size: 12,
        color: Color.rgb255(24, 88, 170)
      )
      |> Page.link_to(
        :cover,
        x: Page.content_left(page),
        y: 108,
        width: 120,
        height: 28
      )
    end
  )

PaperForge.write!(document, output_path)

pdf =
  File.read!(output_path)

IO.puts("""
PaperForge 0.4.0 showcase generated.

Path:
#{output_path}

Bytes:
#{byte_size(pdf)}

Flow pages added:
#{flow_report.pages_added}

Flow overflow?:
#{flow_report.overflow?}

Subset plan glyphs:
#{inspect(subset_plan.glyphs)}

Contains /Outlines:
#{String.contains?(pdf, "/Outlines")}

Contains /Names:
#{String.contains?(pdf, "/Names")}

Contains /Dest:
#{String.contains?(pdf, "/Dest")}

Contains /Annots:
#{String.contains?(pdf, "/Annots")}

Registered font programs:
#{map_size(document.font_program_registry)}
""")
