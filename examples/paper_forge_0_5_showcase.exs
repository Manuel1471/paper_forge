alias PaperForge.Color
alias PaperForge.Flow
alias PaperForge.Page

root_dir =
  Path.expand("..", __DIR__)

output_path =
  Path.join(root_dir, "tmp/paper_forge_0_5_showcase.pdf")

font_path =
  Path.join(root_dir, "test/fixtures/fonts/SFNSMono.ttf")

image_path =
  Path.join(root_dir, "assets/rgba_1000.png")

File.mkdir_p!(Path.dirname(output_path))

rows =
  [["ID", "Block", "Report"]] ++
    for index <- 1..28 do
      [
        index,
        "Unified row #{index}",
        "measured, paginated, rendered"
      ]
    end

{document, report} =
  PaperForge.new(
    compress: true,
    pdf_version: "1.7",
    default_font: :sfmono_regular
  )
  |> PaperForge.register_font_family(
    :sfmono,
    regular: [path: font_path],
    bold: [path: font_path],
    italic: [path: font_path],
    bold_italic: [path: font_path]
  )
  |> PaperForge.page_template(
    :unified_report,
    size: :a4,
    margins: [top: 74, right: 54, bottom: 74, left: 54],
    header: fn page, context ->
      Page.text(page, "PaperForge 0.5.0 Unified Layout",
        x: context.content_left,
        y: 34,
        width: context.content_width,
        align: :center,
        font: :sfmono,
        weight: :bold,
        size: 10,
        color: Color.rgb255(28, 58, 110)
      )
    end,
    footer: "Page {page} of {total}"
  )
  |> PaperForge.metadata(
    title: "PaperForge 0.5.0 Showcase",
    author: "Manuel Garcia",
    subject: "Unified document layout engine",
    keywords: ["PaperForge", "0.5.0", "layout", "flow", "blocks"],
    creation_date: DateTime.utc_now(),
    modification_date: DateTime.utc_now()
  )
  |> PaperForge.layout(
    fn flow ->
      flow
      |> Flow.heading("Unified Document Layout", level: 1)
      |> Flow.paragraph(
        "This PDF is rendered with the new block engine. The first pass measures and paginates blocks. The second pass renders final pages with total page count, headers, footers, destinations, and bookmarks."
      )
      |> Flow.list(
        [
          "Common block model",
          "Deterministic two-pass rendering",
          "PageContext for headers, footers, and custom blocks",
          "Automatic headings, destinations, and bookmarks",
          "Tables, lists, images, separators, spacers, and page breaks"
        ],
        type: :ordered
      )
      |> Flow.separator()
      |> Flow.section(:tables, [title: "Tables and repeated headers"], fn section ->
        section
        |> Flow.paragraph(
          "The table below is a flow block. It is measured and split across pages when needed."
        )
        |> Flow.table(
          ["ID", "Block", "Report"],
          rows,
          repeat_header: true,
          font: :sfmono,
          size: 8,
          row_height: 24
        )
      end)
      |> Flow.page_break()
      |> Flow.section(:media, [title: "Images and custom blocks"], fn section ->
        section
        |> Flow.image(
          image_path,
          width: 140,
          height: 140,
          align: :center,
          caption: "PNG RGBA image inside the unified flow"
        )
        |> Flow.spacer(18)
        |> Flow.custom(
          fn page, context ->
            page
            |> Page.rectangle(
              x: context.content_left,
              y: context.content_top,
              width: context.content_width,
              height: 48,
              fill: true,
              stroke: true,
              fill_color: Color.rgb255(238, 242, 248),
              stroke_color: Color.rgb255(120, 145, 180)
            )
            |> Page.text(
              "Custom block rendered on page #{context.page_number} of #{context.total_pages}",
              x: context.content_left + 12,
              y: context.content_top + 29,
              font: :sfmono,
              size: 10
            )
          end,
          height: 60
        )
      end)
    end,
    template: :unified_report
  )

PaperForge.write!(document, output_path)

debug_report =
  PaperForge.debug(document,
    show_margins: true,
    show_blocks: true,
    show_page_breaks: true
  )

IO.puts("""
PaperForge 0.5.0 showcase generated.

Path:
#{output_path}

Layout pages:
#{report.pages}

Layout blocks:
#{report.blocks}

Placements:
#{length(report.placements)}

Debug report:
#{inspect(debug_report)}
""")
