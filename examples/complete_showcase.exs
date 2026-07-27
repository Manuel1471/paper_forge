alias PaperForge.Color
alias PaperForge.Page

root_dir =
  Path.expand("..", __DIR__)

output_path =
  Path.join(root_dir, "tmp/paper_forge_complete_showcase.pdf")

font_path =
  Path.join(root_dir, "test/fixtures/fonts/SFNSMono.ttf")

jpeg_path =
  Path.join(root_dir, "assets/sample_converted.jpg")

png_path =
  Path.join(root_dir, "assets/rgba_1000.png")

File.mkdir_p!(Path.dirname(output_path))

document =
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
  |> PaperForge.default_font(:sfmono_regular)
  |> PaperForge.metadata(
    title: "PaperForge Complete Showcase",
    author: "Manuel Garcia",
    subject: "Complex PDF covering PaperForge 0.1.0 through 0.3.0 features",
    keywords: [
      "PaperForge",
      "Elixir",
      "PDF",
      "Unicode",
      "TrueType",
      "PNG",
      "JPEG"
    ],
    creator: "PaperForge example",
    producer: "PaperForge",
    creation_date: DateTime.utc_now(),
    modification_date: DateTime.utc_now()
  )
  |> PaperForge.add_page(
    [
      size: :a4,
      origin: :top_left,
      margins: [
        top: 54,
        right: 54,
        bottom: 54,
        left: 54
      ]
    ],
    fn page ->
      left = Page.content_left(page)
      width = Page.content_width(page)

      page
      |> Page.text(
        "PaperForge Complete Showcase",
        y: 58,
        width: width,
        align: :center,
        font: :sfmono,
        weight: :bold,
        size: 24,
        color: Color.rgb255(28, 58, 110)
      )
      |> Page.text(
        "Pure Elixir PDF generation — Unicode — Images — Layout",
        y: 92,
        width: width,
        align: :center,
        font: :sfmono,
        style: :italic,
        size: 11,
        color: Color.rgb255(80, 80, 80)
      )
      |> Page.line(
        x1: left,
        y1: 116,
        x2: left + width,
        y2: 116,
        width: 1,
        color: Color.rgb255(45, 90, 160)
      )
      |> Page.paragraph(
        """
        Este PDF combina las capacidades agregadas en las versiones recientes:
        metadatos Unicode, compresion, coordenadas top-left, fuentes TrueType
        embebidas, texto Unicode visible, medicion real de texto, tablas,
        links, imagenes JPEG, PNG con transparencia y flujo automatico.
        """,
        y: 142,
        width: width,
        font: :sfmono,
        size: 11,
        line_height: 16
      )
      |> Page.table(
        [
          ["Feature", "Covered in this PDF"],
          ["Text", "Default font, family variants, alignment, paragraphs"],
          ["Unicode", "Español: ñ ü ¿ ¡ — Greek: Ω — Cyrillic: Привет"],
          ["Images", "JPEG, PNG RGBA, alpha soft mask, deduplication"],
          ["Layout", "Margins, top-left origin, tables, page flow"],
          ["PDF", "Compression, xref, metadata, link annotations"]
        ],
        x: left,
        y: 255,
        width: width,
        font: :sfmono,
        size: 9,
        row_height: 30,
        padding: 7,
        header: true
      )
      |> Page.rectangle(
        x: left,
        y: 465,
        width: width,
        height: 96,
        fill: true,
        stroke: true,
        fill_color: Color.rgb255(238, 242, 248),
        stroke_color: Color.rgb255(120, 145, 180),
        line_width: 1
      )
      |> Page.text(
        "Project repository",
        x: left + 18,
        y: 500,
        font: :sfmono,
        weight: :bold,
        size: 12,
        color: Color.rgb255(24, 88, 170)
      )
      |> Page.paragraph(
        "The rectangle below contains a real PDF URI annotation. Open the generated PDF and click the label.",
        x: left + 18,
        y: 522,
        width: width - 36,
        font: :sfmono,
        size: 9,
        line_height: 13
      )
      |> Page.link(
        "https://github.com/Manuel1471/paper_forge",
        x: left + 18,
        y: 480,
        width: 170,
        height: 30
      )
      |> Page.circle(
        x: left + 62,
        y: 640,
        radius: 34,
        fill: true,
        stroke: true,
        fill_color: Color.rgb255(247, 199, 84),
        stroke_color: Color.rgb255(130, 90, 25),
        line_width: 2
      )
      |> Page.rectangle(
        x: left + 140,
        y: 606,
        width: 92,
        height: 68,
        fill: true,
        stroke: true,
        fill_color: Color.rgb255(196, 224, 210),
        stroke_color: Color.rgb255(45, 105, 80),
        line_width: 2
      )
      |> Page.line(
        x1: left + 282,
        y1: 606,
        x2: left + 398,
        y2: 674,
        width: 2,
        color: Color.rgb255(170, 60, 60)
      )
      |> Page.text(
        "Vector graphics",
        y: 720,
        width: width,
        align: :center,
        font: :sfmono,
        size: 11
      )
    end
  )
  |> PaperForge.add_page(
    [
      size: :letter,
      orientation: :landscape,
      origin: :top_left,
      margins: 42
    ],
    fn page ->
      left = Page.content_left(page)
      width = Page.content_width(page)

      page
      |> Page.text(
        "Images, Alpha, And Deduplication",
        y: 44,
        width: width,
        align: :center,
        font: :sfmono,
        weight: :bold,
        size: 20,
        color: Color.rgb255(28, 58, 110)
      )
      |> Page.paragraph(
        "This page embeds one JPEG and reuses the same RGBA PNG twice. The PNG alpha channel is represented with a PDF soft mask.",
        y: 82,
        width: width,
        font: :sfmono,
        size: 10,
        line_height: 14
      )
      |> Page.image(
        jpeg_path,
        x: left,
        y: 136,
        width: 220
      )
      |> Page.rectangle(
        x: left + 260,
        y: 136,
        width: 180,
        height: 180,
        fill: true,
        stroke: false,
        fill_color: Color.rgb255(47, 94, 150)
      )
      |> Page.image(
        png_path,
        x: left + 290,
        y: 166,
        width: 120
      )
      |> Page.rectangle(
        x: left + 490,
        y: 136,
        width: 180,
        height: 180,
        fill: true,
        stroke: false,
        fill_color: Color.rgb255(240, 205, 80)
      )
      |> Page.image(
        png_path,
        x: left + 520,
        y: 166,
        width: 120
      )
      |> Page.table(
        [
          ["Asset", "Behavior"],
          ["JPEG", "Embedded directly with /DCTDecode"],
          ["PNG RGBA", "Embedded with /FlateDecode and /SMask"],
          ["Repeated PNG", "Deduplicated through the image registry"]
        ],
        x: left,
        y: 370,
        width: width,
        font: :sfmono,
        size: 9,
        row_height: 28,
        header: true
      )
    end
  )
  |> PaperForge.add_flow(
    for index <- 1..90 do
      "Flow paragraph #{index}: Información con acentos, símbolos € © ™ — Greek Ω — Cyrillic Привет. This text demonstrates automatic page breaks."
    end,
    [
      size: :a4,
      origin: :top_left,
      margins: 64
    ],
    font: :sfmono,
    size: 10,
    line_height: 14,
    gap: 6
  )

PaperForge.write!(document, output_path)

pdf =
  File.read!(output_path)

IO.puts("""
Complex PaperForge PDF generated.

Path:
#{output_path}

Bytes:
#{byte_size(pdf)}

Registered fonts:
#{map_size(document.font_registry.fonts)}

Registered images:
#{map_size(document.image_registry.images)}

Contains /ToUnicode:
#{String.contains?(pdf, "/ToUnicode")}

Contains /SMask:
#{String.contains?(pdf, "/SMask")}

Contains link annotations:
#{String.contains?(pdf, "/Annots")}
""")
