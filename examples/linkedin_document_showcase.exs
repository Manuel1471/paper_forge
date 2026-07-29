alias PaperForge.{Color, Flow, Page}

File.mkdir_p!("tmp")

navy = Color.rgb255(16, 38, 55)
teal = Color.rgb255(12, 126, 126)
mint = Color.rgb255(220, 244, 238)
coral = Color.rgb255(239, 111, 92)
ink = Color.rgb255(31, 42, 49)
muted = Color.rgb255(91, 105, 112)
paper = Color.rgb255(247, 250, 249)

metric = fn page, x, y, width, value, label, change ->
  page
  |> Page.rectangle(
    x: x,
    y: y,
    width: width,
    height: 78,
    fill: true,
    stroke: false,
    fill_color: paper
  )
  |> Page.text(value, x: x + 14, y: y + 25, size: 19, weight: :bold, color: navy)
  |> Page.text(label, x: x + 14, y: y + 45, size: 8, color: muted)
  |> Page.text(change,
    x: x + 14,
    y: y + 62,
    size: 8,
    weight: :bold,
    color: teal
  )
end

document =
  PaperForge.new(compress: true)
  |> PaperForge.metadata(
    title: "Northstar Goods FY 2026 Investor Brief",
    author: "Northstar Goods"
  )
  |> PaperForge.page_template(
    :investor,
    size: :a4,
    margins: [top: 42, right: 48, bottom: 42, left: 48],
    footer: fn page, context ->
      page
      |> Page.line(
        x1: context.content_left,
        y1: context.content_bottom + 10,
        x2: context.content_right,
        y2: context.content_bottom + 10,
        width: 0.5,
        color: Color.rgb255(205, 214, 211)
      )
      |> Page.text("NORTHSTAR GOODS  /  FY 2026",
        x: context.content_left,
        y: context.content_bottom + 27,
        size: 7,
        color: muted
      )
      |> Page.text("#{context.page_number} / #{context.total_pages}",
        x: context.content_right - 50,
        y: context.content_bottom + 27,
        width: 50,
        align: :right,
        size: 7,
        color: muted
      )
    end
  )

{document, report} =
  PaperForge.layout(
    document,
    fn flow ->
      flow
      |> Flow.custom(
        fn page, ctx ->
          x = ctx.block_x
          y = ctx.block_y
          w = ctx.block_width

          page =
            page
            |> Page.rectangle(
              x: x,
              y: y,
              width: w,
              height: 184,
              fill: true,
              stroke: false,
              fill_color: navy
            )
            |> Page.text("NORTHSTAR / INVESTOR BRIEF",
              x: x + 24,
              y: y + 29,
              size: 8,
              weight: :bold,
              color: mint
            )
            |> Page.paragraph("Profitable growth,\nbuilt to last.",
              x: x + 24,
              y: y + 70,
              width: 390,
              size: 28,
              line_height: 31,
              weight: :bold,
              color: Color.white()
            )
            |> Page.text("FY 2026 RESULTS",
              x: x + w - 138,
              y: y + 51,
              width: 114,
              align: :right,
              size: 9,
              color: mint
            )
            |> Page.text("$612M",
              x: x + w - 160,
              y: y + 108,
              width: 136,
              align: :right,
              size: 28,
              weight: :bold,
              color: Color.white()
            )
            |> Page.text("NET REVENUE",
              x: x + w - 160,
              y: y + 128,
              width: 136,
              align: :right,
              size: 7,
              color: mint
            )

          card_w = (w - 24) / 3

          page
          |> metric.(x, y + 204, card_w, "17.8%", "ADJUSTED EBITDA", "+240 bps YoY")
          |> metric.(x + card_w + 12, y + 204, card_w, "$1.42", "DILUTED EPS", "+22.4% YoY")
          |> metric.(
            x + 2 * (card_w + 12),
            y + 204,
            card_w,
            "84%",
            "CASH CONVERSION",
            "+9 pts YoY"
          )
          |> Page.text("THE YEAR IN ONE VIEW",
            x: x,
            y: y + 322,
            size: 8,
            weight: :bold,
            color: teal
          )
          |> Page.text("Momentum across every channel",
            x: x,
            y: y + 354,
            size: 20,
            weight: :bold,
            color: navy
          )
          |> Page.paragraph(
            "Northstar Goods paired double-digit growth with disciplined execution. Premium retail expanded, direct subscriptions improved retention, and operating leverage funded the next wave of product innovation.",
            x: x,
            y: y + 382,
            width: w * 0.58,
            size: 10,
            line_height: 15,
            color: ink
          )
          |> Page.rectangle(
            x: x + w * 0.64,
            y: y + 326,
            width: w * 0.36,
            height: 145,
            fill: true,
            stroke: false,
            fill_color: mint
          )
          |> Page.text("2027 OUTLOOK",
            x: x + w * 0.64 + 18,
            y: y + 355,
            size: 8,
            weight: :bold,
            color: teal
          )
          |> Page.text("8-10%",
            x: x + w * 0.64 + 18,
            y: y + 393,
            size: 25,
            weight: :bold,
            color: navy
          )
          |> Page.text("organic revenue growth",
            x: x + w * 0.64 + 18,
            y: y + 414,
            size: 8,
            color: muted
          )
          |> Page.text("18-19%",
            x: x + w * 0.64 + 18,
            y: y + 447,
            size: 16,
            weight: :bold,
            color: coral
          )
          |> Page.text("EBITDA margin target",
            x: x + w * 0.64 + 84,
            y: y + 447,
            size: 8,
            color: muted
          )
        end,
        height: 500
      )
      |> Flow.page_break()
      |> Flow.heading("Performance dashboard",
        destination: :performance,
        size: 23,
        color: navy,
        space_after: 3
      )
      |> Flow.paragraph("A balanced scorecard for growth, margin and capital efficiency.",
        size: 10,
        color: muted,
        space_after: 22
      )
      |> Flow.chart(
        [{"Q1", 128}, {"Q2", 143}, {"Q3", 158}, {"Q4", 183}],
        height: 150,
        color: teal,
        space_after: 32
      )
      |> Flow.heading("Revenue by channel",
        destination: :segments,
        level: 2,
        size: 16,
        color: navy,
        space_after: 8
      )
      |> Flow.table(
        ["Channel", "Revenue", "Growth", "Strategic signal"],
        [
          ["Retail", "$318M", "+11.6%", "Premium mix and new doors"],
          ["Foodservice", "$146M", "+14.2%", "National account wins"],
          ["Direct", "$96M", "+21.8%", "Retention reached 91%"],
          ["International", "$52M", "+8.7%", "Measured market expansion"]
        ],
        column_widths: [100, 82, 74, 195],
        row_height: 34,
        padding: 8,
        header_fill_color: navy,
        header_color: Color.white(),
        stripe_fill_color: paper,
        stroke_color: Color.rgb255(211, 220, 217),
        space_after: 26
      )
      |> Flow.custom(
        fn page, ctx ->
          page
          |> Page.rectangle(
            x: ctx.block_x,
            y: ctx.block_y,
            width: ctx.block_width,
            height: 74,
            fill: true,
            stroke: false,
            fill_color: mint
          )
          |> Page.rectangle(
            x: ctx.block_x,
            y: ctx.block_y,
            width: 5,
            height: 74,
            fill: true,
            stroke: false,
            fill_color: coral
          )
          |> Page.text("MANAGEMENT PRIORITY",
            x: ctx.block_x + 20,
            y: ctx.block_y + 25,
            size: 8,
            weight: :bold,
            color: teal
          )
          |> Page.text("Invest through the cycle while keeping leverage below 2.0x.",
            x: ctx.block_x + 20,
            y: ctx.block_y + 50,
            size: 12,
            weight: :bold,
            color: navy
          )
        end,
        height: 74
      )
    end,
    template: :investor
  )

PaperForge.write!(document, "tmp/paper_forge_linkedin_showcase.pdf")
IO.inspect(%{pages: report.pages, blocks: report.blocks}, label: "LinkedIn showcase")
