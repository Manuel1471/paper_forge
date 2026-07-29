alias PaperForge.{Color, Flow, Page}

File.mkdir_p!("tmp")

navy = Color.rgb255(24, 43, 62)
blue = Color.rgb255(47, 111, 151)
ice = Color.rgb255(239, 246, 248)
ink = Color.rgb255(40, 48, 55)
muted = Color.rgb255(104, 114, 120)

document =
  PaperForge.new(compress: true)
  |> PaperForge.metadata(title: "Invoice PF-2607", author: "Beacon & Row")
  |> PaperForge.page_template(
    :invoice,
    size: :a4,
    margins: [top: 48, right: 50, bottom: 46, left: 50],
    footer: fn page, context ->
      page
      |> Page.text("BEACON & ROW  /  HELLO@BEACONROW.EXAMPLE",
        x: context.content_left,
        y: context.content_bottom + 25,
        size: 7,
        color: muted
      )
      |> Page.text("PF-2607  /  #{context.page_number}",
        x: context.content_right - 90,
        y: context.content_bottom + 25,
        width: 90,
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

          page
          |> Page.rectangle(
            x: x,
            y: y,
            width: w,
            height: 116,
            fill: true,
            stroke: false,
            fill_color: navy
          )
          |> Page.text("B&R", x: x + 22, y: y + 40, size: 18, weight: :bold, color: Color.white())
          |> Page.text("BEACON & ROW",
            x: x + 22,
            y: y + 61,
            size: 7,
            color: Color.rgb255(181, 212, 225)
          )
          |> Page.text("INVOICE",
            x: x + w - 170,
            y: y + 50,
            width: 148,
            align: :right,
            size: 27,
            weight: :bold,
            color: Color.white()
          )
          |> Page.text("PF-2607",
            x: x + w - 170,
            y: y + 73,
            width: 148,
            align: :right,
            size: 9,
            color: Color.rgb255(181, 212, 225)
          )
          |> Page.text("BILL TO",
            x: x,
            y: y + 151,
            size: 7,
            weight: :bold,
            color: blue
          )
          |> Page.text("Meridian Retail Co.",
            x: x,
            y: y + 178,
            size: 13,
            weight: :bold,
            color: navy
          )
          |> Page.paragraph("Ana Torres\nMonterrey, Nuevo Leon, MX",
            x: x,
            y: y + 190,
            width: 220,
            size: 9,
            line_height: 13,
            color: muted
          )
          |> Page.text("ISSUED",
            x: x + w - 184,
            y: y + 151,
            size: 7,
            weight: :bold,
            color: blue
          )
          |> Page.text("29 JUL 2026", x: x + w - 184, y: y + 177, size: 10, color: ink)
          |> Page.text("DUE",
            x: x + w - 82,
            y: y + 151,
            size: 7,
            weight: :bold,
            color: blue
          )
          |> Page.text("28 AUG 2026", x: x + w - 82, y: y + 177, size: 10, color: ink)
        end,
        height: 236
      )
      |> Flow.table(
        ["DESCRIPTION", "QTY", "RATE", "AMOUNT"],
        [
          ["Brand system refinement", "1", "$6,800", "$6,800"],
          ["Campaign art direction", "1", "$5,200", "$5,200"],
          ["Retail launch toolkit", "1", "$4,600", "$4,600"],
          ["Production management", "1", "$1,800", "$1,800"]
        ],
        column_widths: [220, 52, 90, 89],
        row_height: 38,
        padding: 9,
        header_fill_color: blue,
        header_color: Color.white(),
        stripe_fill_color: ice,
        stroke_color: Color.rgb255(215, 225, 229),
        space_after: 20
      )
      |> Flow.custom(
        fn page, ctx ->
          x = ctx.block_x
          y = ctx.block_y
          w = ctx.block_width

          page
          |> Page.text("PAYMENT DETAILS", x: x, y: y + 17, size: 7, weight: :bold, color: blue)
          |> Page.paragraph("Bank transfer\nAccount ending 4182\nReference PF-2607",
            x: x,
            y: y + 32,
            width: 190,
            size: 9,
            line_height: 14,
            color: ink
          )
          |> Page.rectangle(
            x: x + w - 190,
            y: y,
            width: 190,
            height: 112,
            fill: true,
            stroke: false,
            fill_color: ice
          )
          |> Page.text("Subtotal",
            x: x + w - 172,
            y: y + 25,
            size: 9,
            color: muted
          )
          |> Page.text("$18,400",
            x: x + w - 86,
            y: y + 25,
            width: 68,
            align: :right,
            size: 9,
            color: ink
          )
          |> Page.text("Tax",
            x: x + w - 172,
            y: y + 48,
            size: 9,
            color: muted
          )
          |> Page.text("$2,944",
            x: x + w - 86,
            y: y + 48,
            width: 68,
            align: :right,
            size: 9,
            color: ink
          )
          |> Page.line(
            x1: x + w - 172,
            y1: y + 62,
            x2: x + w - 18,
            y2: y + 62,
            width: 0.5,
            color: Color.rgb255(185, 203, 210)
          )
          |> Page.text("TOTAL DUE",
            x: x + w - 172,
            y: y + 88,
            size: 8,
            weight: :bold,
            color: blue
          )
          |> Page.text("$21,344",
            x: x + w - 108,
            y: y + 91,
            width: 90,
            align: :right,
            size: 17,
            weight: :bold,
            color: navy
          )
          |> Page.text("Thank you. We loved building this with you.",
            x: x,
            y: y + 143,
            size: 13,
            weight: :bold,
            color: navy
          )
          |> Page.text("Questions? hello@beaconrow.example",
            x: x,
            y: y + 164,
            size: 8,
            color: muted
          )
        end,
        height: 178
      )
    end,
    template: :invoice
  )

PaperForge.write!(document, "tmp/paper_forge_0_6_authoring.pdf")
IO.inspect(%{pages: report.pages, placements: length(report.placements)}, label: "Invoice")
