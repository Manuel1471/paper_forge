alias PaperForge.{Color, Flow, Page}

File.mkdir_p!("tmp")

ink = Color.rgb255(23, 34, 43)
navy = Color.rgb255(19, 43, 58)
teal = Color.rgb255(13, 132, 125)
mint = Color.rgb255(218, 242, 235)
coral = Color.rgb255(239, 102, 82)
gold = Color.rgb255(244, 194, 79)
fog = Color.rgb255(243, 247, 246)
muted = Color.rgb255(100, 112, 117)
line = Color.rgb255(207, 217, 214)

metric_card = fn page, x, y, width, value, label, detail, accent ->
  page
  |> Page.rectangle(
    x: x,
    y: y,
    width: width,
    height: 96,
    fill: true,
    stroke: false,
    fill_color: fog
  )
  |> Page.rectangle(
    x: x,
    y: y,
    width: 5,
    height: 96,
    fill: true,
    stroke: false,
    fill_color: accent
  )
  |> Page.text(value, x: x + 17, y: y + 34, size: 22, weight: :bold, color: navy)
  |> Page.text(label,
    x: x + 17,
    y: y + 57,
    size: 7,
    weight: :bold,
    color: muted
  )
  |> Page.text(detail, x: x + 17, y: y + 78, size: 8, color: accent)
end

footer = fn page, context ->
  page
  |> Page.line(
    x1: context.content_left,
    y1: context.content_bottom + 18,
    x2: context.content_right,
    y2: context.content_bottom + 18,
    width: 0.5,
    color: line
  )
  |> Page.text("LUMA MOBILITY  /  ANNUAL REVIEW 2026",
    x: context.content_left,
    y: context.content_bottom + 38,
    size: 7,
    color: muted
  )
  |> Page.text("#{context.page_number} / #{context.total_pages}",
    x: context.content_right - 60,
    y: context.content_bottom + 38,
    width: 60,
    align: :right,
    size: 7,
    color: muted
  )
end

document =
  PaperForge.new(compress: true, pdf_version: "1.7")
  |> PaperForge.metadata(
    title: "Luma Mobility Annual Review 2026",
    author: "Luma Mobility",
    subject: "PaperForge 1.0 signature showcase",
    keywords: ["PaperForge", "Elixir", "PDF", "annual report", "showcase"]
  )
  |> PaperForge.attach(
    "luma_2026_summary.csv",
    "metric,value\nrevenue,284000000\nrides,18700000\ncities,28\nrenewable_energy,0.91\n",
    mime: "text/csv",
    description: "Fictional source data for the annual review"
  )
  |> PaperForge.style(:body, size: 9.5, line_height: 14.5, color: ink)
  |> PaperForge.page_template(
    :signature,
    size: :a4,
    margins: [top: 48, right: 48, bottom: 54, left: 48],
    footer: footer
  )

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
            height: 474,
            fill: true,
            stroke: false,
            fill_color: navy
          )
          |> Page.text("LUMA / 2026",
            x: x + 28,
            y: y + 35,
            size: 8,
            weight: :bold,
            color: mint
          )
          |> Page.text("MOVE BETTER",
            x: x + w - 150,
            y: y + 35,
            width: 122,
            align: :right,
            size: 8,
            weight: :bold,
            color: mint
          )
          |> Page.paragraph("The city,\nin motion.",
            x: x + 28,
            y: y + 92,
            width: 340,
            size: 35,
            line_height: 39,
            weight: :bold,
            color: Color.white()
          )
          |> Page.paragraph(
            "Luma Mobility Annual Review 2026",
            x: x + 28,
            y: y + 194,
            width: 250,
            size: 11,
            line_height: 15,
            color: Color.rgb255(188, 214, 218)
          )
          |> Page.circle(
            x: x + w - 78,
            y: y + 115,
            radius: 37,
            fill: true,
            stroke: false,
            fill_color: coral
          )
          |> Page.circle(
            x: x + w - 148,
            y: y + 216,
            radius: 15,
            fill: true,
            stroke: false,
            fill_color: gold
          )
          |> Page.line(
            x1: x + 28,
            y1: y + 346,
            x2: x + w - 28,
            y2: y + 346,
            width: 1,
            color: Color.rgb255(72, 103, 116)
          )
          |> Page.text("18.7M",
            x: x + 28,
            y: y + 390,
            size: 22,
            weight: :bold,
            color: Color.white()
          )
          |> Page.text("RIDES",
            x: x + 28,
            y: y + 411,
            size: 7,
            color: mint
          )
          |> Page.text("28",
            x: x + 192,
            y: y + 390,
            size: 22,
            weight: :bold,
            color: Color.white()
          )
          |> Page.text("CITIES",
            x: x + 192,
            y: y + 411,
            size: 7,
            color: mint
          )
          |> Page.text("91%",
            x: x + 332,
            y: y + 390,
            size: 22,
            weight: :bold,
            color: Color.white()
          )
          |> Page.text("RENEWABLE ENERGY",
            x: x + 332,
            y: y + 411,
            size: 7,
            color: mint
          )
          |> Page.text("A calmer, cleaner way through the places we share.",
            x: x,
            y: y + 532,
            width: w,
            align: :center,
            size: 14,
            weight: :bold,
            color: navy
          )
          |> Page.text("Fictional company. Real PaperForge output.",
            x: x,
            y: y + 560,
            width: w,
            align: :center,
            size: 8,
            color: muted
          )
        end,
        height: 590
      )
      |> Flow.page_break()
      |> Flow.heading("A year of useful momentum",
        destination: :momentum,
        size: 25,
        color: navy,
        space_after: 5
      )
      |> Flow.paragraph(
        "Growth became more durable, operations became cleaner, and every major customer measure moved in the right direction.",
        style: :body,
        color: muted,
        space_after: 22
      )
      |> Flow.custom(
        fn page, context ->
          x = context.block_x
          y = context.block_y
          w = context.block_width
          card_w = (w - 24) / 3

          page
          |> metric_card.(x, y, card_w, "$284M", "NET REVENUE", "+18.6% YoY", teal)
          |> metric_card.(x + card_w + 12, y, card_w, "4.8", "APP RATING", "+0.3 points", coral)
          |> metric_card.(x + 2 * (card_w + 12), y, card_w, "42", "NPS", "+11 points", gold)
        end,
        height: 96
      )
      |> Flow.spacer(24)
      |> Flow.heading("Quarterly net revenue",
        destination: :revenue,
        level: 2,
        size: 16,
        color: navy,
        space_after: 6
      )
      |> Flow.paragraph("USD millions, showing a steady expansion in network productivity.",
        size: 8,
        color: muted,
        space_after: 14
      )
      |> Flow.chart(
        [{"Q1", 58}, {"Q2", 66}, {"Q3", 74}, {"Q4", 86}],
        height: 138,
        color: teal,
        gap: 16,
        space_after: 28
      )
      |> Flow.columns(
        2,
        [
          "Luma added six cities without diluting service quality. Average vehicle availability reached 96%, supported by better demand forecasting and denser charging coverage.",
          "Subscription members completed 38% more rides and showed stronger retention. Product investment focused on reliability, transparent pricing, and safer late-night journeys.",
          "Operations reduced energy consumed per ride by 14%. Renewable contracts now cover 91% of electricity used across charging and maintenance hubs.",
          "The attached CSV contains the compact source summary used by this fictional report."
        ],
        style: :body,
        gap: 28,
        space_after: 12
      )
      |> Flow.footnote(
        "All company names, values, and operating results in this showcase are fictional."
      )
      |> Flow.page_break()
      |> Flow.heading("Growth with discipline",
        destination: :discipline,
        size: 25,
        color: navy,
        space_after: 5
      )
      |> Flow.paragraph(
        "A concise operating scorecard keeps the story readable while preserving the detail behind each result.",
        style: :body,
        color: muted,
        space_after: 20
      )
      |> Flow.table(
        ["Priority", "2026 result", "Change", "What moved"],
        [
          [
            "Network quality",
            "96% availability",
            "+4 pts",
            "Predictive maintenance and denser hubs"
          ],
          ["Member growth", "2.4M members", "+31%", "Simpler plans and improved retention"],
          [
            "Unit economics",
            "$1.84 contribution",
            "+22%",
            "Utilization, pricing, and fleet life"
          ],
          ["Safety", "1.8 incidents / 100K", "-37%", "Lighting, routing, and rider education"],
          ["Energy", "91% renewable", "+16 pts", "Long-term supply contracts"],
          ["Team", "84% engagement", "+7 pts", "Manager training and clearer progression"]
        ],
        column_widths: [120, 105, 72, 202],
        row_height: 36,
        cell_line_height: 11,
        padding: 8,
        repeat_header: true,
        row_split: :split,
        header_fill_color: navy,
        header_color: Color.white(),
        stripe_fill_color: fog,
        stroke_color: line,
        size: 8,
        numbered: true,
        caption: "Operating priorities and measured outcomes",
        space_after: 26
      )
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
            height: 118,
            fill: true,
            stroke: false,
            fill_color: mint
          )
          |> Page.rectangle(
            x: x,
            y: y,
            width: 6,
            height: 118,
            fill: true,
            stroke: false,
            fill_color: coral
          )
          |> Page.text("2027 COMMITMENT",
            x: x + 24,
            y: y + 29,
            size: 7,
            weight: :bold,
            color: teal
          )
          |> Page.paragraph("Every new ride will add less noise,\nless carbon, and more access.",
            x: x + 24,
            y: y + 48,
            width: w - 190,
            size: 15,
            line_height: 19,
            weight: :bold,
            color: navy
          )
          |> Page.text("100%",
            x: x + w - 132,
            y: y + 62,
            width: 106,
            align: :right,
            size: 23,
            weight: :bold,
            color: coral
          )
          |> Page.text("renewable target",
            x: x + w - 132,
            y: y + 84,
            width: 106,
            align: :right,
            size: 7,
            color: muted
          )
        end,
        height: 118
      )
      |> Flow.page_break()
      |> Flow.heading("Designed for decisions",
        destination: :decisions,
        size: 25,
        color: navy,
        space_after: 5
      )
      |> Flow.paragraph(
        "The final page turns the report itself into the product demonstration.",
        style: :body,
        color: muted,
        space_after: 16
      )
      |> Flow.svg(
        """
        <svg viewBox="0 0 500 54">
          <defs>
            <clipPath id="band"><rect x="0" y="0" width="500" height="54"/></clipPath>
          </defs>
          <g clip-path="url(#band)" style="fill:#daf2eb;stroke:#0d847d;stroke-width:2">
            <path d="M 0 42 C 90 4 155 4 245 35 C 335 55 405 62 500 12 L 500 54 L 0 54 Z"/>
            <polygon points="420,8 446,27 420,46" style="fill:#ef6652;stroke:none"/>
          </g>
        </svg>
        """,
        height: 54,
        space_after: 18
      )
      |> Flow.grid(
        2,
        [
          "DOCUMENT FLOW\nMeasured blocks, pagination, tables, notes and columns.",
          "PDF NAVIGATION\nDestinations, outlines, internal links and page context.",
          "NATIVE VISUALS\nCharts, SVG paths, clipping, QR codes and barcodes.",
          "PORTABLE OUTPUT\nPure Elixir generation with validation and deterministic bytes."
        ],
        cell_height: 84,
        gap: 14,
        fill_color: fog,
        stroke_color: line,
        size: 9,
        line_height: 13,
        space_after: 26
      )
      |> Flow.custom(
        fn page, context ->
          page
          |> Page.rectangle(
            x: context.block_x,
            y: context.block_y,
            width: context.block_width,
            height: 78,
            fill: true,
            stroke: false,
            fill_color: navy
          )
          |> Page.text("A PDF engine should disappear behind the document.",
            x: context.block_x + 22,
            y: context.block_y + 34,
            size: 14,
            weight: :bold,
            color: Color.white()
          )
          |> Page.text("PaperForge",
            x: context.block_x + 22,
            y: context.block_y + 58,
            size: 8,
            color: mint
          )
        end,
        height: 78
      )
      |> Flow.spacer(24)
      |> Flow.heading("Explore the package", level: 2, size: 16, color: navy, space_after: 6)
      |> Flow.paragraph(
        "Scan to open Hex. The barcode is a vector release reference.",
        size: 8,
        color: muted,
        space_after: 12
      )
      |> Flow.qr_code("https://hex.pm/packages/paper_forge",
        width: 78,
        height: 78,
        space_after: 14
      )
      |> Flow.barcode("10002026", width: 190, height: 50, space_after: 18)
    end,
    template: :signature
  )

output = "tmp/paper_forge_1_0_signature_showcase.pdf"
PaperForge.write!(document, output)

IO.inspect(
  %{
    output: output,
    pages: report.pages,
    placements: length(report.placements),
    validation: PaperForge.validate!(document)
  },
  label: "PaperForge 1.0 signature showcase"
)
