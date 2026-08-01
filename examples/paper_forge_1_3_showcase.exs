alias PaperForge.{Color, Flow, Page}

File.mkdir_p!("tmp")

data_path = System.get_env("PAPERFORGE_DATA", Path.join(__DIR__, "data/lumen_atlas.json"))

data = data_path |> File.read!() |> Jason.decode!()

company = data["company"]
year = data["year"]
cover_title = data["cover_title"]
review_label = data["review_label"]
summary = data["summary"]
headline = data["headline"]
headline_revenue = data["headline_revenue"]
headline_growth = data["headline_growth"]
metrics = data["metrics"]
chart = Enum.map(data["chart"], fn [label, value] -> {label, value} end)
portfolio_revenue = data["portfolio_revenue"]
portfolio_growth = data["portfolio_growth"]
survey_url = data["survey_url"]
survey_intro = data["survey_intro"]
report_id = data["report_id"]
attachment_name = data["attachment_name"]

font_regular = "/System/Library/Fonts/Supplemental/Georgia.ttf"
font_bold = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
font_italic = "/System/Library/Fonts/Supplemental/Georgia Italic.ttf"
font_bold_italic = "/System/Library/Fonts/Supplemental/Georgia Bold Italic.ttf"

ink = Color.rgb255(22, 33, 47)
navy = Color.rgb255(17, 43, 63)
teal = Color.rgb255(0, 145, 126)
mint = Color.rgb255(220, 245, 235)
coral = Color.rgb255(244, 101, 82)
gold = Color.rgb255(246, 190, 61)
sky = Color.rgb255(93, 178, 226)
violet = Color.rgb255(111, 86, 168)
muted = Color.rgb255(91, 105, 116)
paper = Color.rgb255(245, 248, 247)
line = Color.rgb255(208, 220, 218)

rows =
  data["rows"]
  |> Enum.with_index()
  |> Enum.map(fn {[program, market, revenue, growth, signal], index} ->
    tint = if(rem(index, 2) == 0, do: paper, else: Color.white())
    growth_color = if(String.starts_with?(growth, "-"), do: coral, else: teal)

    [
      Flow.cell(program, color: navy, fill_color: tint, valign: :middle),
      Flow.cell(market, fill_color: tint, valign: :middle),
      Flow.cell(revenue, align: :right, fill_color: tint, valign: :middle),
      Flow.cell(growth,
        align: :center,
        color: growth_color,
        fill_color: tint,
        valign: :middle
      ),
      Flow.cell(signal, fill_color: tint, valign: :middle)
    ]
  end)

document =
  PaperForge.new(compress: true, default_font: :georgia_regular)
  |> PaperForge.register_font_family(
    :georgia,
    regular: [path: font_regular],
    bold: [path: font_bold],
    italic: [path: font_italic],
    bold_italic: [path: font_bold_italic]
  )
  |> PaperForge.default_font(:georgia_regular)
  |> PaperForge.metadata(
    title: "#{company} #{year} Impact and Growth Review",
    author: company,
    subject: "PaperForge 1.3 secure, accessible, declarative document showcase",
    keywords: ["PaperForge", "Elixir", "PDF", "annual report", "climate technology"]
  )
  |> PaperForge.attach(
    attachment_name,
    data["source_csv"],
    mime: "text/csv",
    description: data["attachment_description"]
  )
  |> PaperForge.style(:body, size: 9.5, line_height: 14, color: ink)
  |> PaperForge.style(:section_title,
    weight: :bold,
    size: 23,
    color: navy,
    space_after: 10
  )
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
          fill_color: Color.rgb255(232, 244, 250)
        )
        |> Page.rectangle(
          x: context.block_x,
          y: context.block_y,
          width: 5,
          height: context.block_height,
          fill: true,
          stroke: false,
          fill_color: violet
        )
        |> Page.text(assigns.label,
          x: context.block_x + 20,
          y: context.block_y + 24,
          size: 7,
          weight: :bold,
          color: violet
        )
        |> Page.text(assigns.text,
          x: context.block_x + 20,
          y: context.block_y + 49,
          width: context.block_width - 40,
          size: 12,
          weight: :bold,
          color: ink
        )
      end,
      height: 72
    )
  end)
  |> PaperForge.page_template(
    :base,
    size: :a4,
    margins: [top: 52, right: 48, bottom: 58, left: 48],
    footer: fn page, context ->
      page
      |> Page.line(
        x1: context.content_left,
        y1: context.content_bottom + 12,
        x2: context.content_right,
        y2: context.content_bottom + 12,
        width: 0.5,
        color: line
      )
      |> Page.text("#{String.upcase(company)}  /  IMPACT & GROWTH #{year}",
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

report_flow = fn flow ->
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
        height: 252,
        fill: true,
        stroke: false,
        fill_color: navy
      )
      |> Page.rectangle(
        x: x + w * 0.64,
        y: y,
        width: w * 0.36,
        height: 252,
        fill: true,
        stroke: false,
        fill_color: violet
      )
      |> Page.text("#{String.upcase(company)} / #{year}",
        x: x + 26,
        y: y + 32,
        size: 8,
        weight: :bold,
        color: Color.rgb255(184, 226, 218)
      )
      |> Page.paragraph(cover_title,
        x: x + 26,
        y: y + 72,
        width: 310,
        size: 34,
        line_height: 38,
        weight: :bold,
        color: Color.white()
      )
      |> Page.text(review_label,
        x: x + 26,
        y: y + 194,
        size: 11,
        style: :italic,
        color: Color.rgb255(183, 211, 217)
      )
      |> Page.circle(
        x: x + w - 76,
        y: y + 68,
        radius: 27,
        fill: true,
        stroke: false,
        fill_color: gold
      )
      |> Page.circle(
        x: x + w - 128,
        y: y + 132,
        radius: 13,
        fill: true,
        stroke: false,
        fill_color: sky
      )
      |> Page.text("A clearer view of what moves us",
        x: x,
        y: y + 302,
        size: 23,
        weight: :bold,
        color: navy
      )
      |> Page.paragraph(
        summary,
        x: x,
        y: y + 338,
        width: w * 0.66,
        size: 10,
        line_height: 15,
        color: ink
      )
      |> Page.rectangle(
        x: x + w * 0.72,
        y: y + 300,
        width: w * 0.28,
        height: 126,
        fill: true,
        stroke: false,
        fill_color: Color.rgb255(255, 243, 213)
      )
      |> Page.text(headline_revenue,
        x: x + w * 0.72 + 16,
        y: y + 346,
        size: 25,
        weight: :bold,
        color: navy
      )
      |> Page.text("CLEAN REVENUE",
        x: x + w * 0.72 + 16,
        y: y + 372,
        size: 7,
        color: violet
      )
      |> Page.text(headline_growth,
        x: x + w * 0.72 + 16,
        y: y + 402,
        size: 10,
        weight: :bold,
        color: coral
      )
      |> Page.rectangle(
        x: x,
        y: y + 452,
        width: w,
        height: 82,
        fill: true,
        stroke: false,
        fill_color: mint
      )
      |> Page.rectangle(
        x: x,
        y: y + 452,
        width: 8,
        height: 82,
        fill: true,
        stroke: false,
        fill_color: teal
      )
      |> Page.text("#{year} IN ONE SENTENCE",
        x: x + 24,
        y: y + 480,
        size: 7,
        weight: :bold,
        color: teal
      )
      |> Page.text(headline,
        x: x + 24,
        y: y + 513,
        size: 17,
        weight: :bold,
        color: navy
      )
      |> Page.circle(
        x: x + w - 42,
        y: y + 493,
        radius: 16,
        fill: true,
        stroke: false,
        fill_color: coral
      )
      |> Page.text("01",
        x: x,
        y: y + 574,
        size: 17,
        weight: :bold,
        color: teal
      )
      |> Page.text("SCALE",
        x: x + 40,
        y: y + 566,
        size: 7,
        weight: :bold,
        color: teal
      )
      |> Page.paragraph(
        data["scale_copy"],
        x: x + 40,
        y: y + 582,
        width: 112,
        size: 8.5,
        line_height: 12,
        color: ink
      )
      |> Page.text("02",
        x: x + 174,
        y: y + 574,
        size: 17,
        weight: :bold,
        color: coral
      )
      |> Page.text("TRUST",
        x: x + 214,
        y: y + 566,
        size: 7,
        weight: :bold,
        color: coral
      )
      |> Page.paragraph(
        data["trust_copy"],
        x: x + 214,
        y: y + 582,
        width: 112,
        size: 8.5,
        line_height: 12,
        color: ink
      )
      |> Page.text("03",
        x: x + 348,
        y: y + 574,
        size: 17,
        weight: :bold,
        color: sky
      )
      |> Page.text("HORIZON",
        x: x + 388,
        y: y + 566,
        size: 7,
        weight: :bold,
        color: sky
      )
      |> Page.paragraph(
        data["horizon_copy"],
        x: x + 388,
        y: y + 582,
        width: 111,
        size: 8.5,
        line_height: 12,
        color: ink
      )
    end,
    height: 650
  )
  |> Flow.page_break()
  |> Flow.custom(
    fn page, context ->
      x = context.block_x
      y = context.block_y
      w = context.block_width

      entries = [
        {"01", "Performance overview", "Momentum, margin and cash conversion", "03", :performance,
         teal},
        {"02", "Operating portfolio", "Programs, regions and measured outcomes", "04", :portfolio,
         coral},
        {"03", "Rider survey & PDF craft", "A useful call to action, built with native vectors",
         "05", :capabilities, violet}
      ]

      page =
        page
        |> Page.text("INSIDE THE REPORT",
          x: x,
          y: y + 12,
          size: 8,
          weight: :bold,
          color: teal
        )
        |> Page.text("Move through the story.",
          x: x,
          y: y + 54,
          size: 28,
          weight: :bold,
          color: navy
        )
        |> Page.paragraph(
          "Three chapters connect the headline signal to operating detail and the technology that generated every page.",
          x: x,
          y: y + 78,
          width: w * 0.7,
          size: 10,
          line_height: 15,
          color: muted
        )
        |> Page.circle(
          x: x + w - 38,
          y: y + 42,
          radius: 22,
          fill: true,
          stroke: false,
          fill_color: gold
        )

      page =
        entries
        |> Enum.with_index()
        |> Enum.reduce(page, fn {{number, title, description, page_number, destination, accent},
                                 index},
                                current ->
          row_y = y + 142 + index * 98

          current
          |> Page.rectangle(
            x: x,
            y: row_y,
            width: w,
            height: 82,
            fill: true,
            stroke: true,
            fill_color: if(rem(index, 2) == 0, do: paper, else: Color.white()),
            stroke_color: line,
            line_width: 0.7
          )
          |> Page.rectangle(
            x: x,
            y: row_y,
            width: 7,
            height: 82,
            fill: true,
            stroke: false,
            fill_color: accent
          )
          |> Page.text(number,
            x: x + 22,
            y: row_y + 49,
            size: 25,
            weight: :bold,
            color: accent
          )
          |> Page.text(title,
            x: x + 82,
            y: row_y + 32,
            size: 15,
            weight: :bold,
            color: navy
          )
          |> Page.text(description,
            x: x + 82,
            y: row_y + 57,
            size: 8.5,
            color: muted
          )
          |> Page.circle(
            x: x + w - 39,
            y: row_y + 41,
            radius: 18,
            fill: true,
            stroke: false,
            fill_color: accent
          )
          |> Page.text(page_number,
            x: x + w - 54,
            y: row_y + 46,
            width: 30,
            align: :center,
            size: 10,
            weight: :bold,
            color: Color.white()
          )
          |> Page.link_to(destination,
            x: x,
            y: row_y,
            width: w,
            height: 82
          )
        end)

      page
      |> Page.rectangle(
        x: x,
        y: y + 464,
        width: w,
        height: 110,
        fill: true,
        stroke: false,
        fill_color: violet
      )
      |> Page.rectangle(
        x: x,
        y: y + 464,
        width: 9,
        height: 110,
        fill: true,
        stroke: false,
        fill_color: gold
      )
      |> Page.text("PAPERFORGE 1.0",
        x: x + 24,
        y: y + 493,
        size: 8,
        weight: :bold,
        color: mint
      )
      |> Page.text("A real PDF. Every destination linked.",
        x: x + 24,
        y: y + 528,
        size: 17,
        weight: :bold,
        color: Color.white()
      )
      |> Page.text("Click any chapter above to navigate.",
        x: x + 24,
        y: y + 552,
        size: 8.5,
        color: Color.rgb255(190, 214, 219)
      )
    end,
    height: 574
  )
  |> Flow.page_break()
  |> Flow.custom(
    fn page, context ->
      page
      |> Page.text("02 / PERFORMANCE",
        x: context.block_x,
        y: context.block_y + 10,
        size: 7.5,
        weight: :bold,
        color: violet
      )
      |> Page.text("A year of useful momentum",
        x: context.block_x,
        y: context.block_y + 48,
        size: 25,
        weight: :bold,
        color: navy
      )
      |> Page.paragraph(
        data["performance_summary"],
        x: context.block_x,
        y: context.block_y + 70,
        width: context.block_width * 0.82,
        size: 9.5,
        line_height: 14,
        color: muted
      )
      |> Page.circle(
        x: context.block_x + context.block_width - 28,
        y: context.block_y + 38,
        radius: 17,
        fill: true,
        stroke: false,
        fill_color: coral
      )
    end,
    height: 112,
    space_after: 18,
    destination: :performance
  )
  |> Flow.custom(
    fn page, context ->
      accents = [teal, coral, gold]

      cards =
        metrics
        |> Enum.zip(accents)
        |> Enum.map(fn {%{"value" => value, "label" => label, "change" => change}, accent} ->
          {accent, value, label, change}
        end)

      card_width = (context.block_width - 24) / 3

      cards
      |> Enum.with_index()
      |> Enum.reduce(page, fn {{accent, value, label, change}, index}, current ->
        x = context.block_x + index * (card_width + 12)

        current
        |> Page.rectangle(
          x: x,
          y: context.block_y,
          width: card_width,
          height: 88,
          fill: true,
          stroke: false,
          fill_color: paper
        )
        |> Page.rectangle(
          x: x,
          y: context.block_y,
          width: 6,
          height: 88,
          fill: true,
          stroke: false,
          fill_color: accent
        )
        |> Page.text(value,
          x: x + 18,
          y: context.block_y + 34,
          size: 20,
          weight: :bold,
          color: navy
        )
        |> Page.text(label,
          x: x + 18,
          y: context.block_y + 55,
          size: 6.5,
          weight: :bold,
          color: muted
        )
        |> Page.text(change,
          x: x + 18,
          y: context.block_y + 75,
          size: 7.5,
          color: accent
        )
      end)
    end,
    height: 88,
    space_after: 24
  )
  |> Flow.chart(
    chart,
    height: 142,
    color: violet,
    space_after: 28
  )
  |> Flow.component(:callout, %{
    label: "OPERATING SIGNAL",
    text: data["operating_signal"]
  })
  |> Flow.spacer(14)
  |> Flow.custom(
    fn page, context ->
      x = context.block_x
      y = context.block_y
      w = context.block_width
      column_width = (w - 30) / 2

      page
      |> Page.text("WHAT DROVE THE YEAR",
        x: x,
        y: y + 10,
        size: 7.5,
        weight: :bold,
        color: teal
      )
      |> Page.line(
        x1: x,
        y1: y + 22,
        x2: x + w,
        y2: y + 22,
        width: 0.7,
        color: line
      )
      |> Page.circle(
        x: x + 10,
        y: y + 48,
        radius: 6,
        fill: true,
        stroke: false,
        fill_color: teal
      )
      |> Page.text(data["driver_left_title"],
        x: x + 28,
        y: y + 51,
        size: 11,
        weight: :bold,
        color: navy
      )
      |> Page.paragraph(
        data["driver_left_copy"],
        x: x + 28,
        y: y + 70,
        width: column_width - 28,
        size: 8.5,
        line_height: 12,
        color: ink
      )
      |> Page.circle(
        x: x + column_width + 26,
        y: y + 48,
        radius: 6,
        fill: true,
        stroke: false,
        fill_color: gold
      )
      |> Page.text(data["driver_right_title"],
        x: x + column_width + 44,
        y: y + 51,
        size: 11,
        weight: :bold,
        color: navy
      )
      |> Page.paragraph(
        data["driver_right_copy"],
        x: x + column_width + 44,
        y: y + 70,
        width: column_width - 28,
        size: 8.5,
        line_height: 12,
        color: ink
      )
      |> Page.rectangle(
        x: x,
        y: y + 126,
        width: w,
        height: 34,
        fill: true,
        stroke: false,
        fill_color: navy
      )
      |> Page.text("Explore the operating portfolio",
        x: x + 16,
        y: y + 147,
        size: 9,
        weight: :bold,
        color: Color.white()
      )
      |> Page.text("PAGE 04",
        x: x + w - 72,
        y: y + 147,
        width: 56,
        align: :right,
        size: 7,
        weight: :bold,
        color: gold
      )
      |> Page.link_to(:portfolio, x: x, y: y + 126, width: w, height: 34)
    end,
    height: 160
  )
  |> Flow.footnote(
    1,
    "Financial values are fictional, unaudited, and included solely to demonstrate PaperForge."
  )
  |> Flow.page_break()
  |> Flow.custom(
    fn page, context ->
      x = context.block_x
      y = context.block_y
      w = context.block_width

      page
      |> Page.text("03 / PORTFOLIO",
        x: x,
        y: y + 10,
        size: 7.5,
        weight: :bold,
        color: coral
      )
      |> Page.text("Where growth became durable",
        x: x,
        y: y + 48,
        size: 25,
        weight: :bold,
        color: navy
      )
      |> Page.paragraph(
        data["portfolio_summary"],
        x: x,
        y: y + 70,
        width: w * 0.78,
        size: 9.5,
        line_height: 14,
        color: muted
      )
      |> Page.rectangle(
        x: x,
        y: y + 112,
        width: w,
        height: 54,
        fill: true,
        stroke: false,
        fill_color: navy
      )
      |> Page.text("8",
        x: x + 20,
        y: y + 146,
        size: 18,
        weight: :bold,
        color: gold
      )
      |> Page.text("PROGRAMS",
        x: x + 50,
        y: y + 142,
        size: 7,
        weight: :bold,
        color: Color.white()
      )
      |> Page.text(portfolio_revenue,
        x: x + 182,
        y: y + 146,
        size: 18,
        weight: :bold,
        color: mint
      )
      |> Page.text("PORTFOLIO REVENUE",
        x: x + 252,
        y: y + 142,
        size: 7,
        weight: :bold,
        color: Color.white()
      )
      |> Page.text(portfolio_growth,
        x: x + 370,
        y: y + 146,
        size: 18,
        weight: :bold,
        color: Color.rgb255(255, 189, 174)
      )
      |> Page.text("AVG. GROWTH",
        x: x + 438,
        y: y + 142,
        size: 7,
        weight: :bold,
        color: Color.white()
      )
    end,
    height: 166,
    space_after: 18,
    destination: :portfolio
  )
  |> Flow.table(
    ["Program", "Market", "#{year} revenue", "Growth", "Strategic signal"],
    rows,
    column_widths: [92, 70, 67, 58, 212],
    row_height: 40,
    cell_line_height: 11.5,
    padding: 8,
    row_split: :keep,
    repeat_header: true,
    header_fill_color: teal,
    header_color: Color.white(),
    stroke_color: line,
    size: 8.2,
    space_after: 20
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
        height: 62,
        fill: true,
        stroke: false,
        fill_color: Color.rgb255(255, 247, 225)
      )
      |> Page.rectangle(
        x: x,
        y: y,
        width: 7,
        height: 62,
        fill: true,
        stroke: false,
        fill_color: gold
      )
      |> Page.text("PORTFOLIO READ",
        x: x + 20,
        y: y + 24,
        size: 7,
        weight: :bold,
        color: violet
      )
      |> Page.text(data["portfolio_read"],
        x: x + 20,
        y: y + 45,
        size: 10.5,
        weight: :bold,
        color: navy
      )
      |> Page.circle(
        x: x + w - 158,
        y: y + 22,
        radius: 4,
        fill: true,
        stroke: false,
        fill_color: teal
      )
      |> Page.text("GROWTH",
        x: x + w - 146,
        y: y + 25,
        size: 6,
        color: muted
      )
      |> Page.circle(
        x: x + w - 81,
        y: y + 22,
        radius: 4,
        fill: true,
        stroke: false,
        fill_color: coral
      )
      |> Page.text("PLANNED DECLINE",
        x: x + w - 69,
        y: y + 25,
        size: 6,
        color: muted
      )
    end,
    height: 62
  )
  |> Flow.footnote(
    2,
    "The attached #{attachment_name} file contains the summarized source values.",
    marker: false
  )
  |> Flow.page_break()
  |> Flow.custom(
    fn page, context ->
      x = context.block_x
      y = context.block_y
      w = context.block_width
      matrix = Qiroex.to_matrix!(survey_url, level: :m, quiet_zone: 4)
      qr_size = 118
      qr_x = x + w - 146
      qr_y = y + 228
      module_size = qr_size / length(matrix)

      page =
        page
        |> Page.rectangle(
          x: x,
          y: y,
          width: w,
          height: 164,
          fill: true,
          stroke: false,
          fill_color: navy
        )
        |> Page.rectangle(
          x: x + w - 128,
          y: y,
          width: 128,
          height: 164,
          fill: true,
          stroke: false,
          fill_color: violet
        )
        |> Page.text("04 / LISTENING",
          x: x + 24,
          y: y + 32,
          size: 7.5,
          weight: :bold,
          color: mint
        )
        |> Page.text("The next route starts",
          x: x + 24,
          y: y + 75,
          size: 24,
          weight: :bold,
          color: Color.white()
        )
        |> Page.text("with a better question.",
          x: x + 24,
          y: y + 108,
          size: 24,
          weight: :bold,
          color: Color.white()
        )
        |> Page.paragraph(
          survey_intro,
          x: x + 24,
          y: y + 130,
          width: w - 190,
          size: 8.5,
          line_height: 12,
          color: Color.rgb255(196, 218, 223)
        )
        |> Page.circle(
          x: x + w - 64,
          y: y + 55,
          radius: 24,
          fill: true,
          stroke: false,
          fill_color: gold
        )
        |> Page.circle(
          x: x + w - 92,
          y: y + 105,
          radius: 10,
          fill: true,
          stroke: false,
          fill_color: sky
        )
        |> Page.rectangle(
          x: x,
          y: y + 188,
          width: w,
          height: 224,
          fill: true,
          stroke: false,
          fill_color: mint
        )
        |> Page.rectangle(
          x: qr_x - 12,
          y: qr_y - 12,
          width: qr_size + 24,
          height: qr_size + 24,
          fill: true,
          stroke: false,
          fill_color: Color.white()
        )
        |> Page.text("RIDER PULSE / 2027",
          x: x + 24,
          y: y + 222,
          size: 7.5,
          weight: :bold,
          color: teal
        )
        |> Page.text("Tell us what would make",
          x: x + 24,
          y: y + 262,
          size: 19,
          weight: :bold,
          color: navy
        )
        |> Page.text("your next ride better.",
          x: x + 24,
          y: y + 288,
          size: 19,
          weight: :bold,
          color: navy
        )
        |> Page.paragraph(
          "A three-minute survey for #{company} riders about vehicle availability, safe late-night travel, fair pricing and the neighborhoods the electric network should connect next.",
          x: x + 24,
          y: y + 312,
          width: 260,
          size: 9.5,
          line_height: 14,
          color: ink
        )
        |> Page.text("3 MINUTES",
          x: x + 24,
          y: y + 373,
          size: 7,
          weight: :bold,
          color: violet
        )
        |> Page.text("ANONYMOUS",
          x: x + 106,
          y: y + 373,
          size: 7,
          weight: :bold,
          color: violet
        )
        |> Page.text("OPEN THROUGH 31 JAN",
          x: x + 196,
          y: y + 373,
          size: 7,
          weight: :bold,
          color: violet
        )
        |> Page.link(survey_url,
          x: qr_x - 12,
          y: qr_y - 12,
          width: qr_size + 24,
          height: qr_size + 24
        )

      page =
        matrix
        |> Enum.with_index()
        |> Enum.reduce(page, fn {row, row_index}, current ->
          row
          |> Enum.with_index()
          |> Enum.reduce(current, fn
            {1, column_index}, qr_page ->
              Page.rectangle(qr_page,
                x: qr_x + column_index * module_size,
                y: qr_y + row_index * module_size,
                width: module_size + 0.01,
                height: module_size + 0.01,
                fill: true,
                stroke: false,
                fill_color: navy
              )

            {_value, _column_index}, qr_page ->
              qr_page
          end)
        end)

      cards = [
        {teal, "01", "Availability", "Were charged vehicles ready when riders needed them?"},
        {coral, "02", "Night safety", "Which stops, routes or hours need more confidence?"},
        {sky, "03", "Network reach", "Which neighborhood should #{company} connect next?"}
      ]

      page =
        cards
        |> Enum.with_index()
        |> Enum.reduce(page, fn {{accent, number, title, copy}, index}, current ->
          card_width = (w - 24) / 3
          card_x = x + index * (card_width + 12)

          current
          |> Page.rectangle(
            x: card_x,
            y: y + 438,
            width: card_width,
            height: 92,
            fill: true,
            stroke: true,
            fill_color: paper,
            stroke_color: line,
            line_width: 0.7
          )
          |> Page.text(number,
            x: card_x + 14,
            y: y + 469,
            size: 16,
            weight: :bold,
            color: accent
          )
          |> Page.text(title,
            x: card_x + 46,
            y: y + 463,
            size: 10,
            weight: :bold,
            color: navy
          )
          |> Page.paragraph(copy,
            x: card_x + 14,
            y: y + 490,
            width: card_width - 28,
            size: 7.8,
            line_height: 11,
            color: muted
          )
        end)

      barcode = PaperForge.Barcode.interleaved_2_of_5(report_id)
      total_units = Enum.reduce(barcode, 0, fn {_bar?, units}, total -> total + units end)
      barcode_width = 160
      unit = barcode_width / total_units

      {page, _cursor} =
        Enum.reduce(barcode, {page, x}, fn {bar?, units}, {current, cursor} ->
          next =
            if bar? do
              Page.rectangle(current,
                x: cursor,
                y: y + 575,
                width: units * unit,
                height: 34,
                fill: true,
                stroke: false,
                fill_color: navy
              )
            else
              current
            end

          {next, cursor + units * unit}
        end)

      page
      |> Page.text("REPORT ID  /  #{report_id}",
        x: x,
        y: y + 628,
        size: 7,
        weight: :bold,
        color: muted
      )
      |> Page.paragraph(
        "Native QR and barcode vectors remain sharp at any zoom. The report also contains linked destinations, outlines, footnotes and an embedded CSV source file.",
        x: x + 205,
        y: y + 577,
        width: w - 205,
        size: 8.2,
        line_height: 12,
        color: ink
      )
    end,
    height: 645,
    destination: :capabilities
  )
end

{document, report} =
  PaperForge.layout(document, report_flow, template: :report)

document =
  document
  |> PaperForge.comply(profiles: [:pdf_ua_1], language: "en-US")
  |> PaperForge.protect(
    identifier: "urn:paperforge:lumen-atlas:#{year}",
    policy: [
      allowed_uri_schemes: ["https", "mailto"],
      allowed_hosts: :any,
      allow_attachments: true,
      allowed_attachment_mimes: ["text/csv"],
      max_attachment_bytes: 1_000_000
    ]
  )

output = System.get_env("PAPERFORGE_OUTPUT", "tmp/paper_forge_1_3_showcase.pdf")

write_options =
  case System.get_env("PAPERFORGE_OWNER_PASSWORD") do
    nil ->
      []

    owner_password ->
      [
        security: [
          user_password: System.get_env("PAPERFORGE_USER_PASSWORD", "preview"),
          owner_password: owner_password,
          permissions: [print: :high_resolution, copy: false, modify: false, extract: false]
        ]
      ]
  end

PaperForge.write!(document, output, write_options)

IO.inspect(
  %{
    output: output,
    pages: report.pages,
    blocks: report.blocks,
    placements: length(report.placements)
  },
  label: "PaperForge 1.3 secure and accessible showcase"
)
