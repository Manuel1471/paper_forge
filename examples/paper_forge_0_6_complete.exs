alias PaperForge.{Color, Flow, Page}

File.mkdir_p!("tmp")

navy = Color.rgb255(20, 39, 58)
teal = Color.rgb255(14, 126, 119)
mint = Color.rgb255(223, 243, 238)
coral = Color.rgb255(235, 104, 87)
ink = Color.rgb255(38, 48, 55)
muted = Color.rgb255(98, 110, 116)
paper = Color.rgb255(246, 249, 248)

rows =
  Enum.map(1..12, fn index ->
    region = Enum.at(["North", "Central", "West", "International"], rem(index - 1, 4))
    revenue = 18 + index * 3
    growth = 6.5 + index * 0.7

    [
      "NS-#{2600 + index}",
      region,
      "$#{revenue}M",
      "#{Float.round(growth, 1)}%",
      "Expansion program #{index} combines distribution gains, premium mix, and measured operating investment."
    ]
  end)

document =
  PaperForge.new(compress: true)
  |> PaperForge.metadata(
    title: "Northstar Goods Annual Operating Review",
    author: "Northstar Goods",
    subject: "Complete PaperForge 0.6.0 authoring example"
  )
  |> PaperForge.attach(
    "northstar_operating_data.csv",
    "region,revenue,growth\nNorth,186,12.4\nCentral,148,10.8\nWest,132,14.1\nInternational,96,9.2\n",
    mime: "text/csv",
    description: "Source data for the fictional operating review"
  )
  |> PaperForge.style(:body, size: 9.5, line_height: 14, color: ink)
  |> PaperForge.style(:section_title, size: 21, color: navy, space_after: 10)
  |> PaperForge.component(:callout, fn assigns ->
    Flow.new()
    |> Flow.custom(
      fn page, context ->
        page
        |> Page.rectangle(
          x: context.block_x,
          y: context.block_y,
          width: context.block_width,
          height: context.block_height,
          fill: true,
          stroke: false,
          fill_color: mint
        )
        |> Page.rectangle(
          x: context.block_x,
          y: context.block_y,
          width: 5,
          height: context.block_height,
          fill: true,
          stroke: false,
          fill_color: coral
        )
        |> Page.text(assigns.label,
          x: context.block_x + 20,
          y: context.block_y + 24,
          size: 7,
          weight: :bold,
          color: teal
        )
        |> Page.text(assigns.text,
          x: context.block_x + 20,
          y: context.block_y + 49,
          width: context.block_width - 40,
          size: 12,
          weight: :bold,
          color: navy
        )
      end,
      height: 72
    )
  end)
  |> PaperForge.page_template(
    :base,
    size: :a4,
    margins: [top: 48, right: 48, bottom: 54, left: 48],
    footer: fn page, context ->
      page
      |> Page.line(
        x1: context.content_left,
        y1: context.content_bottom + 12,
        x2: context.content_right,
        y2: context.content_bottom + 12,
        width: 0.5,
        color: Color.rgb255(205, 215, 212)
      )
      |> Page.text("NORTHSTAR GOODS  /  OPERATING REVIEW",
        x: context.content_left,
        y: context.content_bottom + 31,
        size: 7,
        color: muted
      )
      |> Page.text("#{context.page_number} / #{context.total_pages}",
        x: context.content_right - 60,
        y: context.content_bottom + 31,
        width: 60,
        align: :right,
        size: 7,
        color: muted
      )
    end
  )
  |> PaperForge.page_template(:report, extends: :base)

{document, report} =
  PaperForge.layout(
    document,
    fn flow ->
      flow
      |> Flow.custom(
        fn page, context ->
          x = context.block_x
          y = context.block_y
          w = context.block_width

          page
          |> Page.rectangle(
            x: x,
            y: y,
            width: w,
            height: 228,
            fill: true,
            stroke: false,
            fill_color: navy
          )
          |> Page.text("NORTHSTAR / FY 2026",
            x: x + 26,
            y: y + 32,
            size: 8,
            weight: :bold,
            color: mint
          )
          |> Page.paragraph("Annual operating\nreview",
            x: x + 26,
            y: y + 72,
            width: 330,
            size: 31,
            line_height: 34,
            weight: :bold,
            color: Color.white()
          )
          |> Page.text("Built entirely with PaperForge 0.6.0",
            x: x + 26,
            y: y + 180,
            size: 10,
            color: Color.rgb255(183, 211, 217)
          )
          |> Page.circle(
            x: x + w - 66,
            y: y + 58,
            radius: 20,
            fill: true,
            stroke: false,
            fill_color: coral
          )
          |> Page.text("A complete authoring example",
            x: x,
            y: y + 278,
            size: 22,
            weight: :bold,
            color: navy
          )
          |> Page.paragraph(
            "This fictional review combines automatic navigation, reusable components, content-aware tables, page footnotes, endnotes, native charts, vector graphics, QR and barcode output, annotations, and an embedded CSV attachment.",
            x: x,
            y: y + 310,
            width: w * 0.66,
            size: 10,
            line_height: 15,
            color: ink
          )
          |> Page.rectangle(
            x: x + w * 0.72,
            y: y + 275,
            width: w * 0.28,
            height: 126,
            fill: true,
            stroke: false,
            fill_color: mint
          )
          |> Page.text("$562M",
            x: x + w * 0.72 + 16,
            y: y + 320,
            size: 24,
            weight: :bold,
            color: navy
          )
          |> Page.text("NET REVENUE",
            x: x + w * 0.72 + 16,
            y: y + 343,
            size: 7,
            color: teal
          )
          |> Page.text("+13.2% YOY",
            x: x + w * 0.72 + 16,
            y: y + 375,
            size: 10,
            weight: :bold,
            color: coral
          )
        end,
        height: 430
      )
      |> Flow.page_break()
      |> Flow.table_of_contents(title: "Inside this review", size: 10, line_height: 14)
      |> Flow.spacer(28)
      |> Flow.custom(
        fn page, context ->
          page
          |> Page.rectangle(
            x: context.block_x,
            y: context.block_y,
            width: context.block_width,
            height: 250,
            fill: true,
            stroke: false,
            fill_color: navy
          )
          |> Page.text("RELEASE 0.6.0",
            x: context.block_x + 24,
            y: context.block_y + 34,
            size: 8,
            weight: :bold,
            color: mint
          )
          |> Page.paragraph("One document.\nOne layout engine.",
            x: context.block_x + 24,
            y: context.block_y + 62,
            width: 280,
            size: 23,
            line_height: 27,
            weight: :bold,
            color: Color.white()
          )
          |> Page.paragraph(
            "The following pages move from executive summary to operating detail and finish with the PDF-native capabilities used to build the report.",
            x: context.block_x + 24,
            y: context.block_y + 144,
            width: context.block_width - 48,
            size: 9,
            line_height: 14,
            color: Color.rgb255(190, 214, 219)
          )
          |> Page.text("NAVIGATE",
            x: context.block_x + 24,
            y: context.block_y + 205,
            size: 7,
            weight: :bold,
            color: mint
          )
          |> Page.text("MEASURE",
            x: context.block_x + 180,
            y: context.block_y + 205,
            size: 7,
            weight: :bold,
            color: mint
          )
          |> Page.text("DELIVER",
            x: context.block_x + 336,
            y: context.block_y + 205,
            size: 7,
            weight: :bold,
            color: mint
          )
          |> Page.text("Linked contents",
            x: context.block_x + 24,
            y: context.block_y + 226,
            size: 10,
            color: Color.white()
          )
          |> Page.text("Flow diagnostics",
            x: context.block_x + 180,
            y: context.block_y + 226,
            size: 10,
            color: Color.white()
          )
          |> Page.text("Native PDF",
            x: context.block_x + 336,
            y: context.block_y + 226,
            size: 10,
            color: Color.white()
          )
        end,
        height: 250
      )
      |> Flow.page_break()
      |> Flow.heading("Performance overview",
        destination: :performance,
        style: :section_title
      )
      |> Flow.paragraph(
        "Northstar delivered broad-based growth while improving margin quality and cash conversion. The chart and scorecard below are native PDF vectors.",
        style: :body,
        space_after: 18
      )
      |> Flow.grid(
        3,
        [
          "$562M\nRevenue\n+13.2% YoY",
          "18.4%\nEBITDA margin\n+190 bps",
          "87%\nCash conversion\n+11 pts"
        ],
        cell_height: 72,
        gap: 12,
        fill_color: paper,
        stroke_color: Color.rgb255(214, 223, 220),
        space_after: 24
      )
      |> Flow.chart(
        [{"Q1", 118}, {"Q2", 132}, {"Q3", 145}, {"Q4", 167}],
        height: 142,
        color: teal,
        space_after: 28
      )
      |> Flow.component(:callout, %{
        label: "OPERATING SIGNAL",
        text: "Growth accelerated while leverage declined to 1.7x."
      })
      |> Flow.spacer(16)
      |> Flow.footnote(
        1,
        "Financial values are fictional, unaudited, and included solely to demonstrate PaperForge."
      )
      |> Flow.reference(:portfolio, prefix: "Continue to the operating portfolio on page ")
      |> Flow.page_break()
      |> Flow.heading("Operating portfolio", destination: :portfolio, style: :section_title)
      |> Flow.paragraph(
        "Cell content is measured and wrapped automatically. Column widths, row heights, repeated headers, stripes, and pagination are controlled by the table block.",
        style: :body,
        space_after: 14
      )
      |> Flow.table(
        ["Program", "Region", "Revenue", "Growth", "Operating commentary"],
        rows,
        column_widths: [70, 72, 62, 58, 237],
        row_height: 28,
        cell_line_height: 11,
        padding: 7,
        row_split: :split,
        repeat_header: true,
        header_fill_color: navy,
        header_color: Color.white(),
        stripe_fill_color: paper,
        stroke_color: Color.rgb255(207, 218, 214),
        size: 8,
        space_after: 20
      )
      |> Flow.footnote(
        2,
        "The attached northstar_operating_data.csv file contains the summarized source values."
      )
      |> Flow.page_break()
      |> Flow.heading("Document capabilities",
        destination: :capabilities,
        style: :section_title
      )
      |> Flow.columns(
        2,
        [
          "Navigation is generated after pagination, so the contents and cross-references use stable page numbers.",
          "The table engine wraps every cell, derives row heights, repeats headers, and can split oversized rows.",
          "Footnotes reserve bottom-page space and flow to another page if their content cannot fit.",
          "Attachments are emitted as real PDF structures rather than visual placeholders."
        ],
        style: :body,
        gap: 24,
        space_after: 24
      )
      |> Flow.grid(
        2,
        [
          "VECTOR OUTPUT\nQR and barcode remain sharp at any zoom.",
          "PDF STRUCTURE\nAttachment, destinations, outlines and links."
        ],
        cell_height: 68,
        gap: 14,
        fill_color: paper,
        space_after: 22
      )
      |> Flow.heading("Package links", level: 2, size: 15, color: navy, space_after: 8)
      |> Flow.paragraph(
        "Scan the QR code to open the package page. The numeric symbol below is a native vector barcode.",
        style: :body,
        space_after: 12
      )
      |> Flow.qr_code("https://hex.pm/packages/paper_forge",
        width: 82,
        height: 82,
        space_after: 18
      )
      |> Flow.barcode("26062026", width: 190, height: 52, space_after: 28)
      |> Flow.endnotes([], title: "Notes")
    end,
    template: :report
  )

output = "tmp/paper_forge_0_6_complete.pdf"
PaperForge.write!(document, output)

IO.inspect(
  %{
    output: output,
    pages: report.pages,
    blocks: report.blocks,
    placements: length(report.placements)
  },
  label: "PaperForge 0.6.0 complete showcase"
)
