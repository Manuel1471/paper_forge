alias PaperForge.{AcroForm, Color, Flow, Math, Page}

html = """
<html>
  <head>
    <style>
      h1 {
        color: #15364a;
        font-size: 24px;
        font-weight: bold;
        margin-bottom: 12px;
      }

      h2 {
        color: #15364a;
        font-size: 21px;
        font-weight: bold;
        margin-top: 12px;
        margin-bottom: 8px;
      }

      p {
        color: #425b67;
        font-size: 10px;
        margin-bottom: 9px;
      }

      .eyebrow {
        color: #0a8f7a;
        font-size: 8px;
        font-weight: bold;
        margin-bottom: 5px;
      }

      .lead {
        color: #244653;
        font-size: 11px;
        margin-bottom: 14px;
      }

      .signal {
        color: #15364a;
        background-color: #e3f4ef;
        font-size: 14px;
        font-weight: bold;
        margin-top: 14px;
        margin-bottom: 14px;
      }

      #risk {
        color: #a63e35;
        background-color: #fff0ec;
        font-size: 10px;
        font-weight: bold;
        margin-top: 12px;
        margin-bottom: 12px;
      }

      blockquote {
        color: #634e96;
        background-color: #f0ebfa;
        font-size: 12px;
        font-style: italic;
        margin-top: 10px;
        margin-bottom: 14px;
      }

      table {
        color: #243b46;
        font-size: 9px;
        width: 100%;
        border-color: #cad9d6;
        border-width: 0.45pt;
        border-collapse: collapse;
        margin-top: 12px;
        margin-bottom: 16px;
      }

      th {
        color: #ffffff;
        background-color: #173f52;
        padding: 8pt;
        text-align: left;
        vertical-align: middle;
      }

      td {
        color: #243b46;
        padding: 7pt;
        line-height: 12pt;
        vertical-align: middle;
      }

      tr:nth-child(even) {
        background-color: #f0f7f5;
      }

      .page-two {
        page-break-before: always;
      }
    </style>
  </head>
  <body>
    <h1>Turning urban heat into measurable action</h1>
    <p class="lead">
      NOVA MERIDIAN LABS / 2026 FIELD NOTE / A research brief compiled from
      semantic HTML into PaperForge Layout IR.
    </p>
    <p>
      Nova Meridian Labs evaluated reflective roofs, shaded transit corridors, and
      neighborhood cooling hubs across four pilot districts. The study combines
      sensor observations with resident feedback to show where capital creates the
      strongest public benefit.
    </p>
    <p class="signal">
      2.8 C lower peak surface temperature across the highest-performing pilot.
    </p>
    <h2>What changed</h2>
    <ol>
      <li>Tree-canopy coverage increased along 14.2 kilometers of pedestrian routes.</li>
      <li>Reflective roofing reduced afternoon heat retention in public buildings.</li>
      <li>Cooling hubs served 18,420 visits during the eight-week summer window.</li>
    </ol>
    <blockquote>
      The strongest projects paired physical infrastructure with clear community
      stewardship, not isolated construction.
    </blockquote>
    <p id="risk">
      Watch item: District South recorded a 1.4% participation decline after two
      temporary hub closures. The reopening plan is already funded.
    </p>
    <h2>Intervention portfolio</h2>
    <table>
      <thead><tr><th>Program</th><th>Reach</th><th>Next milestone</th></tr></thead>
      <tbody>
        <tr><td>Cool roofs</td><td>38 public buildings</td><td>Procurement complete</td></tr>
        <tr><td>Shade network</td><td>14.2 route kilometers</td><td>Canopy audit in September</td></tr>
        <tr><td>Cooling hubs</td><td>18,420 summer visits</td><td>Permanent sites selected</td></tr>
      </tbody>
    </table>

    <h2 class="page-two">Evidence at a glance</h2>
    <p>
      CSS controls the typography, color, spacing, and this explicit page break.
      The table remains a native PaperForge table, so its cells are
      measured and its text stays searchable.
    </p>
    <table>
      <thead>
        <tr>
          <th>District</th>
          <th>Intervention</th>
          <th>Peak change</th>
          <th>Confidence</th>
        </tr>
      </thead>
      <tbody>
        <tr><td>North</td><td>Reflective roofs</td><td>-2.8 C</td><td>High</td></tr>
        <tr><td>Central</td><td>Shaded corridors</td><td>-2.1 C</td><td>High</td></tr>
        <tr><td>Harbor</td><td>Cooling hubs</td><td>-1.7 C</td><td>Medium</td></tr>
        <tr><td>South</td><td>Mixed program</td><td>-1.3 C</td><td>Medium</td></tr>
      </tbody>
    </table>
    <h2>Interpretation</h2>
    <p>
      North produced the clearest thermal response because reflective surfaces were
      deployed as a connected district program. Central achieved comparable public
      benefit through pedestrian shade, while Harbor delivered the highest direct
      community use. South remains viable, but participation recovery is now the
      leading indicator for its next investment gate.
    </p>
    <blockquote>
      Evidence is strongest when environmental performance and resident behavior
      point in the same direction.
    </blockquote>
    <h2>Model note</h2>
    <p>
      The imported document can continue with native layout blocks. The expression
      below is a Math AST rather than an image, followed by an interactive review
      area implemented with standard PDF structures.
    </p>
  </body>
</html>
"""

{:ok, imported_flow} = PaperForge.Import.html(html, strict_css: true)

equation =
  Math.row([
    Math.symbol("cooling index"),
    Math.symbol("="),
    Math.fraction(
      Math.symbol("temperature delta"),
      Math.symbol("energy invested")
    )
  ])

rounded_rect = fn x, y, width, height, radius ->
  k = radius * 0.552_284_75

  [
    {:move_to, x + radius, y},
    {:line_to, x + width - radius, y},
    {:curve_to, x + width - radius + k, y, x + width, y + radius - k, x + width, y + radius},
    {:line_to, x + width, y + height - radius},
    {:curve_to, x + width, y + height - radius + k, x + width - radius + k, y + height,
     x + width - radius, y + height},
    {:line_to, x + radius, y + height},
    {:curve_to, x + radius - k, y + height, x, y + height - radius + k, x, y + height - radius},
    {:line_to, x, y + radius},
    {:curve_to, x, y + radius - k, x + radius - k, y, x + radius, y},
    :close
  ]
end

review_panel = fn page, context ->
  x = context.block_x
  y = context.block_y
  width = context.block_width

  page
  |> Page.path(rounded_rect.(x, y, width, context.block_height, 9),
    fill: true,
    stroke: false,
    fill_color: Color.rgb255(238, 247, 244),
    origin: :top_left
  )
  |> Page.text("RESEARCH REVIEW",
    x: x + 22,
    y: y + 21,
    size: 8,
    weight: :bold,
    color: Color.rgb255(10, 143, 122)
  )
  |> Page.text("Ready for peer review",
    x: x + 22,
    y: y + 43,
    size: 14,
    weight: :bold,
    color: Color.rgb255(21, 54, 74)
  )
  |> Page.text("Record a reviewer and confirm the methodology.",
    x: x + 22,
    y: y + 65,
    size: 8,
    color: Color.rgb255(78, 101, 110)
  )
  |> Page.text("REVIEWER NAME",
    x: x + 255,
    y: y + 21,
    size: 7,
    weight: :bold,
    color: Color.rgb255(78, 101, 110)
  )
  |> Page.text("Methods and source data reviewed",
    x: x + 275,
    y: y + 76,
    size: 8,
    color: Color.rgb255(36, 70, 83)
  )
  |> Page.line(
    x1: x + 275,
    y1: y + 83,
    x2: x + 410,
    y2: y + 83,
    width: 1.2,
    color: Color.rgb255(111, 86, 168)
  )
end

equation_card = fn flow, label, description, ast, height ->
  Flow.custom(
    flow,
    fn page, context ->
      x = context.block_x
      y = context.block_y
      width = context.block_width
      math_size = 12
      {_expression_width, expression_height} = Math.measure(ast, size: math_size)
      expression_y = y + 37 + max((height - 48 - expression_height) / 2, 0)

      page
      |> Page.path(rounded_rect.(x, y, width, height, 7),
        fill: true,
        stroke: true,
        fill_color: Color.rgb255(248, 250, 249),
        stroke_color: Color.rgb255(211, 222, 220),
        line_width: 0.7,
        origin: :top_left
      )
      |> Page.text(label,
        x: x + 18,
        y: y + 19,
        size: 8,
        weight: :bold,
        color: Color.rgb255(10, 143, 122)
      )
      |> Page.text(description,
        x: x + 132,
        y: y + 19,
        width: width - 150,
        size: 7.5,
        align: :right,
        color: Color.rgb255(89, 108, 116)
      )
      |> Math.render(ast,
        x: x + 20,
        y: expression_y,
        size: math_size,
        color: Color.rgb255(21, 54, 74)
      )
    end,
    height: height,
    space_after: 9
  )
end

scientific_examples = [
  {"FRACTION + ROOT", "Normalized thermal response",
   Math.row([
     Math.symbol("z"),
     Math.symbol("="),
     Math.fraction(
       Math.symbol("observed - baseline"),
       Math.root(Math.symbol("variance"))
     )
   ]), 82},
  {"SUPER + SUBSCRIPT", "Scientific indices and powers",
   Math.row([
     Math.subscript(Math.symbol("CO"), Math.symbol("2")),
     Math.symbol("+"),
     Math.superscript(Math.symbol("x"), Math.symbol("2")),
     Math.symbol("="),
     Math.symbol("42")
   ]), 72},
  {"DEFINITE INTEGRAL", "Accumulated cooling over time",
   Math.row([
     Math.integral(
       Math.symbol("0"),
       Math.symbol("24"),
       Math.subscript(Math.symbol("T"), Math.symbol("surface")),
       "t"
     ),
     Math.symbol("="),
     Math.symbol("daily cooling")
   ]), 88},
  {"MATRIX", "Four-district observation vector",
   Math.row([
     Math.symbol("D"),
     Math.symbol("="),
     Math.matrix([
       [Math.symbol("-2.8"), Math.symbol("-2.1")],
       [Math.symbol("-1.7"), Math.symbol("-1.3")]
     ])
   ]), 104},
  {"COMPOSED AST", "Nested fraction, radical, and exponent",
   Math.row([
     Math.symbol("score"),
     Math.symbol("="),
     Math.fraction(
       Math.superscript(Math.symbol("impact"), Math.symbol("2")),
       Math.root(Math.symbol("cost"), Math.symbol("3"))
     )
   ]), 92}
]

flow =
  imported_flow
  |> Flow.math(equation,
    size: 11.5,
    color: Color.rgb255(21, 54, 74),
    space_before: 8,
    space_after: 14
  )
  |> Flow.custom(review_panel, id: "review-panel", height: 102, space_before: 10)
  |> Flow.page_break()
  |> Flow.heading("Scientific notation gallery",
    level: 1,
    size: 23,
    color: Color.rgb255(21, 54, 74),
    space_after: 8
  )
  |> Flow.paragraph(
    "Every expression below is measured and drawn as native PDF vectors and text from the same composable Math AST used by declarative .paperforge templates.",
    size: 9.5,
    line_height: 14,
    color: Color.rgb255(66, 91, 103),
    space_after: 15
  )

flow =
  Enum.reduce(scientific_examples, flow, fn {label, description, ast, height}, current ->
    equation_card.(current, label, description, ast, height)
  end)

footer = fn page, context ->
  page
  |> Page.line(
    x1: context.content_left,
    y1: context.content_bottom + 12,
    x2: context.content_right,
    y2: context.content_bottom + 12,
    width: 0.5,
    color: Color.rgb255(201, 215, 217)
  )
  |> Page.text("NOVA MERIDIAN LABS / PAPERFORGE 1.4",
    x: context.content_left,
    y: context.content_bottom + 31,
    size: 7,
    color: Color.rgb255(89, 108, 116)
  )
  |> Page.text("#{context.page_number} / #{context.total_pages}",
    x: context.content_right - 50,
    y: context.content_bottom + 31,
    width: 50,
    align: :right,
    size: 7,
    color: Color.rgb255(89, 108, 116)
  )
end

{document, report} =
  PaperForge.new(compress: true)
  |> PaperForge.metadata(
    title: "Nova Meridian Labs Field Note",
    author: "PaperForge",
    subject: "HTML and CSS import showcase"
  )
  |> PaperForge.layout(fn _flow -> flow end,
    page_options: [size: :a4, margins: [top: 54, right: 52, bottom: 58, left: 52]],
    footer: footer
  )

# Layout reports exact block coordinates, allowing PDF-native widgets to align
# with content generated by HTML without hard-coding a page number.
panel = Enum.find(report.placements, &(&1.id == "review-panel"))
page_height = 841.89

pdf_rect = fn left, top, width, height ->
  x1 = panel.x + left
  y2 = page_height - (panel.y + top)
  [x1, y2 - height, x1 + width, y2]
end

document =
  document
  |> AcroForm.add_field(panel.page_number, :text, "reviewer_name",
    rect: pdf_rect.(255, 30, 195, 19),
    tooltip: "Reviewer name",
    border_radius: 5,
    border_width: 0.65,
    border_color: "0.62 0.70 0.73",
    background_color: "1 1 1"
  )
  |> AcroForm.add_field(panel.page_number, :checkbox, "methods_reviewed",
    rect: pdf_rect.(255, 61, 12, 12),
    value: true,
    tooltip: "Confirm that the methods were reviewed",
    border_radius: 3,
    border_width: 0.65,
    border_color: "0.62 0.70 0.73",
    check_color: "0.04 0.56 0.48",
    check_width: 1.2
  )

output =
  System.get_env(
    "PAPERFORGE_OUTPUT",
    Path.expand("../output/pdf/paper_forge_1_4_html_css_showcase.pdf", __DIR__)
  )

File.mkdir_p!(Path.dirname(output))
PaperForge.write!(document, output)

IO.inspect(%{
  output: output,
  pages: report.pages,
  imported_blocks: length(imported_flow.blocks),
  form_fields: 2,
  css_mode: :strict
})
