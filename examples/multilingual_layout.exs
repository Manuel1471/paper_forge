alias PaperForge.Color
alias PaperForge.Page

font_path = "test/fixtures/fonts/SFNSMono.ttf"

document =
  PaperForge.new(default_font: :sfmono)
  |> PaperForge.register_font_family(
    :sfmono,
    regular: [path: font_path],
    bold: [path: font_path],
    italic: [path: font_path],
    bold_italic: [path: font_path]
  )
  |> PaperForge.default_font(:sfmono_regular)
  |> PaperForge.add_page(
    [
      size: :a4,
      origin: :top_left,
      margins: 72
    ],
    fn page ->
      page
      |> Page.text(
        "PaperForge Unicode Layout",
        y: 72,
        width: Page.content_width(page),
        align: :center,
        font: :sfmono,
        weight: :bold,
        size: 22,
        color: Color.rgb255(35, 60, 120)
      )
      |> Page.paragraph(
        "Español: El pingüino comió camarón. Símbolos: € © ™ — …",
        y: 118,
        width: Page.content_width(page),
        font: :sfmono,
        size: 11,
        line_height: 15
      )
      |> Page.table(
        [
          ["Language", "Sample"],
          ["Greek", "Ωμέγα"],
          ["Cyrillic", "Привет"],
          ["Spanish", "¿Listo? ¡Sí!"]
        ],
        y: 180,
        width: Page.content_width(page),
        font: :sfmono,
        size: 10,
        header: true
      )
      |> Page.text(
        "Project repository",
        y: 320,
        font: :sfmono,
        size: 11,
        color: Color.rgb255(20, 90, 170)
      )
      |> Page.link(
        "https://github.com/Manuel1471/paper_forge",
        x: Page.content_left(page),
        y: 302,
        width: 180,
        height: 24
      )
    end
  )
  |> PaperForge.add_flow(
    for index <- 1..80 do
      "Paragraph #{index}: Información multilingual — Привет — Ω — with automatic page breaks."
    end,
    [
      size: :a4,
      margins: 72
    ],
    font: :sfmono,
    size: 10,
    line_height: 14,
    gap: 5
  )

File.mkdir_p!("tmp")
PaperForge.write!(document, "tmp/multilingual_layout.pdf")

IO.puts("Generated tmp/multilingual_layout.pdf")
