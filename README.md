# PaperForge

PaperForge is a pure Elixir PDF generation engine. It builds PDF object graphs,
page content streams, resources, cross-reference tables, trailers, text layout,
vector graphics, metadata, and image XObjects directly in Elixir.

No browser, wkhtmltopdf, Chromium, ImageMagick, Ghostscript, or external
rendering service is required.

PaperForge is currently pre-1.0. The `0.3.x` API is usable, but some details may
still change while layout and image support mature.

## Highlights

- Pure Elixir PDF generation
- Multi-page documents
- PDF 1.4, 1.5, 1.6, and 1.7 headers
- Flate compression enabled by default
- A3, A4, A5, Letter, Legal, and custom page sizes
- Portrait and landscape orientation
- Bottom-left and top-left coordinate systems
- Uniform and side-specific page margins
- Text drawing with color, alignment, and width-aware positioning
- Multiline text boxes with wrapping, explicit line breaks, line height, height
  limits, and overflow reporting
- The 14 standard PDF Type 1 fonts
- Embedded TrueType fonts loaded from paths or binaries
- TrueType PDF width and `/ToUnicode` subsetting for used glyphs
- Font-family registration with regular, bold, italic, and bold italic variants
- Document-level default font selection
- Visible Unicode text through Type 0 / CIDFontType2 fonts
- Identity-H encoding and `/ToUnicode` maps for embedded fonts
- Real TrueType metrics for width, wrapping, and alignment
- Vertical text flow with automatic page breaks
- Basic tables
- URI link annotations
- Lines, rectangles, circles, fill, stroke, and line widths
- RGB and grayscale colors
- JPEG image XObjects with RGB, grayscale, and CMYK support
- PNG image XObjects for non-interlaced 8-bit grayscale, RGB,
  grayscale-alpha, and RGBA images
- PNG transparency through PDF soft masks (`/SMask`)
- Image deduplication by SHA-256 hash
- Unicode-aware document metadata using Latin-1 or UTF-16BE as needed
- Traditional PDF xref table generation

## Installation

PaperForge can be used from GitHub:

```elixir
def deps do
  [
    {:paper_forge,
     github: "Manuel1471/paper_forge",
     tag: "v0.3.0"}
  ]
end
```

For local development against `main`:

```elixir
def deps do
  [
    {:paper_forge,
     github: "Manuel1471/paper_forge",
     branch: "main"}
  ]
end
```

After PaperForge is published to Hex, installation will use:

```elixir
def deps do
  [
    {:paper_forge, "~> 0.3.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

```elixir
alias PaperForge.Color
alias PaperForge.Page

document =
  PaperForge.new(compress: true, pdf_version: "1.7")
  |> PaperForge.register_font(
    :inter,
    path: "assets/fonts/Inter-Regular.ttf"
  )
  |> PaperForge.metadata(
    title: "PaperForge Example",
    author: "Manuel Garcia",
    subject: "Pure Elixir PDF generation",
    keywords: ["Elixir", "PDF", "PaperForge"]
  )
  |> PaperForge.add_page(
    [
      size: :a4,
      origin: :top_left,
      margins: 72
    ],
    fn page ->
      page
      |> Page.text(
        "Informacion del usuario — 你好 — Привет",
        y: 72,
        width: Page.content_width(page),
        align: :center,
        font: :inter,
        size: 28,
        color: Color.rgb255(35, 60, 120)
      )
      |> Page.text_box(
        "PaperForge creates PDF files directly from Elixir data structures, with embedded fonts for visible Unicode text.",
        y: 120,
        width: Page.content_width(page),
        font: :inter,
        size: 12,
        line_height: 17
      )
    end
  )

PaperForge.write!(document, "example.pdf")
```

## Document Options

`PaperForge.new/1` accepts:

- `:compress` - enables Flate compression for page content streams. Defaults to
  `true`.
- `:pdf_version` - sets the PDF header version. Supported values are `"1.4"`,
  `"1.5"`, `"1.6"`, and `"1.7"`. Defaults to `"1.7"`.

```elixir
PaperForge.new()
PaperForge.new(compress: false)
PaperForge.new(pdf_version: "1.4")
PaperForge.new(default_font: :helvetica)
```

## Pages

Add a page with default options:

```elixir
document =
  PaperForge.new()
  |> PaperForge.add_page(fn page ->
    Page.text(page, "Default A4 page", x: 72, y: 750)
  end)
```

Add a page with options:

```elixir
document =
  PaperForge.new()
  |> PaperForge.add_page(
    [
      size: :letter,
      orientation: :landscape,
      origin: :top_left,
      margins: [top: 48, right: 54, bottom: 48, left: 54]
    ],
    fn page ->
      Page.text(page, "Landscape page", y: 48)
    end
  )
```

Supported page sizes:

```elixir
:a3
:a4
:a5
:letter
:legal
```

Custom page sizes use `{width, height}` in PDF points:

```elixir
Page.new(size: {500, 700})
```

All dimensions are expressed in PDF points.

```text
1 point = 1/72 inch
```

## Coordinates And Margins

PaperForge supports both PDF-native bottom-left coordinates and top-left
coordinates.

```elixir
Page.new(origin: :bottom_left)
Page.new(origin: :top_left)
```

You can also set the origin per operation:

```elixir
Page.rectangle(page, x: 72, y: 72, width: 100, height: 40, origin: :top_left)
```

Margins can be uniform:

```elixir
Page.new(margins: 72)
```

Or side-specific:

```elixir
Page.new(margins: [top: 40, right: 50, bottom: 40, left: 50])
```

Content helpers:

```elixir
Page.content_width(page)
Page.content_height(page)
Page.content_left(page)
Page.content_top(page)
Page.content_bottom(page)
```

## Text

Draw a single line of text:

```elixir
Page.text(
  page,
  "Centered title",
  x: Page.content_left(page),
  y: 72,
  width: Page.content_width(page),
  align: :center,
  font: :helvetica_bold,
  size: 24,
  color: Color.black()
)
```

Draw wrapped multiline text:

```elixir
Page.text_box(
  page,
  """
  PaperForge wraps text into multiple lines using built-in font metrics.

  Explicit line breaks are preserved.
  """,
  x: Page.content_left(page),
  y: 120,
  width: Page.content_width(page),
  height: 160,
  font: :times_roman,
  size: 12,
  line_height: 17,
  align: :left
)
```

Supported alignment values:

```elixir
:left
:center
:right
```

## Fonts And Unicode Text

PaperForge supports two font paths: the 14 standard PDF Type 1 fonts and
embedded TrueType fonts.

Standard Type 1 fonts are registered automatically when used:

```elixir
:helvetica
:helvetica_bold
:helvetica_oblique
:helvetica_bold_oblique
:times_roman
:times_bold
:times_italic
:times_bold_italic
:courier
:courier_bold
:courier_oblique
:courier_bold_oblique
:symbol
:zapf_dingbats
```

Standard Type 1 fonts are convenient for simple Latin text, but they are not
full Unicode fonts. For visible Unicode text, register a TrueType `.ttf` font
before adding pages:

```elixir
document =
  PaperForge.new()
  |> PaperForge.register_font(
    :inter,
    path: "assets/fonts/Inter-Regular.ttf"
  )
```

You can also register a font from an in-memory binary:

```elixir
document =
  PaperForge.register_font(
    document,
    :inter,
    data: File.read!("assets/fonts/Inter-Regular.ttf")
  )
```

Then use the registered key in text operations:

```elixir
Page.text(
  page,
  "El pingüino comió camarón — ¿listo? — Привет — Ω",
  x: 72,
  y: 720,
  font: :inter,
  size: 18
)
```

Embedded TrueType fonts are written as PDF Type 0 fonts with a CIDFontType2
descendant, `Identity-H` encoding, a `/FontFile2` stream, widths from the TTF
`hmtx` table, and a `/ToUnicode` CMap so text extraction and search can recover
Unicode characters.

Supported embedded font input:

- TrueType outlines (`.ttf`)
- Unicode `cmap` format 4 or 12
- 8-bit and Unicode text strings supported by the font's glyph coverage

Current limitations:

- OpenType CFF (`OTTO`) and TrueType Collection (`.ttc`) files are not
  supported yet.
- Complex text shaping is not performed, so scripts such as Arabic,
  Devanagari, and advanced ligatures may not render as expected.
- PaperForge subsets the generated PDF width arrays and `/ToUnicode` maps to
  the glyphs used by the document. Physical TTF table reconstruction is not
  implemented yet, so the full `.ttf` program is still embedded in `/FontFile2`.
- A missing glyph raises `PaperForge.FontError`.

### Font Families

Register related TrueType files as a family:

```elixir
document =
  PaperForge.new()
  |> PaperForge.register_font_family(
    :inter,
    regular: [path: "assets/fonts/Inter-Regular.ttf"],
    bold: [path: "assets/fonts/Inter-Bold.ttf"],
    italic: [path: "assets/fonts/Inter-Italic.ttf"],
    bold_italic: [path: "assets/fonts/Inter-BoldItalic.ttf"]
  )
```

Then select a variant with `:weight` and `:style`:

```elixir
Page.text(
  page,
  "Important",
  x: 72,
  y: 720,
  font: :inter,
  weight: :bold,
  style: :italic
)
```

Set a document default font when most text should use the same font:

```elixir
document =
  PaperForge.new()
  |> PaperForge.register_font(:inter, path: "assets/fonts/Inter-Regular.ttf")
  |> PaperForge.default_font(:inter)
```

## Shapes

### Lines

```elixir
Page.line(
  page,
  x1: 72,
  y1: 700,
  x2: 300,
  y2: 700,
  width: 2,
  color: Color.rgb255(40, 70, 140)
)
```

### Rectangles

```elixir
Page.rectangle(
  page,
  x: 72,
  y: 560,
  width: 220,
  height: 100,
  fill: true,
  stroke: true,
  fill_color: Color.rgb255(235, 240, 250),
  stroke_color: Color.rgb255(40, 70, 140),
  line_width: 2
)
```

### Circles

```elixir
Page.circle(
  page,
  x: 400,
  y: 610,
  radius: 50,
  fill: true,
  stroke: true,
  fill_color: Color.rgb255(245, 180, 70),
  stroke_color: Color.rgb255(120, 70, 20),
  line_width: 2
)
```

PaperForge approximates circles using four cubic Bezier curves because PDF does
not provide a native circle operator.

## Colors

RGB values can be expressed from `0` to `1`:

```elixir
Color.rgb(1.0, 0.0, 0.0)
```

Or from `0` to `255`:

```elixir
Color.rgb255(255, 0, 0)
```

Grayscale helpers:

```elixir
Color.gray(0.5)
Color.black()
Color.white()
```

## Images

`Page.image/3` accepts a supported image binary or a file path.

```elixir
png = File.read!("logo.png")

page
|> Page.image(png, x: 72, y: 120, width: 200)
|> Page.image("photo.jpg", x: 72, y: 360, width: 200, height: 120)
```

When only one dimension is supplied, PaperForge preserves the source aspect
ratio:

```elixir
Page.image(page, "logo.png", x: 72, y: 120, width: 200)
Page.image(page, "logo.png", x: 72, y: 120, height: 80)
```

Supported JPEGs:

- grayscale
- RGB
- CMYK

Supported PNGs:

- non-interlaced 8-bit grayscale
- non-interlaced 8-bit RGB
- non-interlaced 8-bit grayscale with alpha
- non-interlaced 8-bit RGBA

PNG alpha is written as a PDF soft mask (`/SMask`). PNG grayscale/RGB images
without alpha use the original compressed `IDAT` data directly with
`/FlateDecode` and PNG predictor decode parameters. JPEG image data is embedded
directly with `/DCTDecode`.

Images are deduplicated by SHA-256 hash, so drawing the same image several times
does not embed duplicate image streams.

## Flow, Tables, And Links

Flow text blocks across pages:

```elixir
document =
  PaperForge.new()
  |> PaperForge.add_flow(
    [
      "First paragraph with enough text to wrap.",
      "Second paragraph. PaperForge creates new pages as needed."
    ],
    [size: :letter, margins: 72],
    font: :helvetica,
    size: 11,
    line_height: 15,
    gap: 8
  )
```

Draw a basic table:

```elixir
page =
  page
  |> Page.table(
    [
      ["Name", "Score"],
      ["Ana", 10],
      ["Luis", 9]
    ],
    x: Page.content_left(page),
    y: 96,
    width: Page.content_width(page),
    header: true
  )
```

Add a URI link annotation:

```elixir
page =
  page
  |> Page.text("Project", x: 72, y: 720)
  |> Page.link(
    "https://github.com/Manuel1471/paper_forge",
    x: 72,
    y: 700,
    width: 180,
    height: 24
  )
```

## Metadata

```elixir
document =
  PaperForge.new()
  |> PaperForge.metadata(
    title: "Reporte de Mexico",
    author: "Manuel Garcia",
    subject: "Informacion \u65E5\u672C\u8A9E",
    keywords: ["report", "elixir", "pdf"],
    creator: "PaperForge",
    producer: "PaperForge",
    creation_date: DateTime.utc_now(),
    modification_date: DateTime.utc_now()
  )
```

Metadata is written into the PDF Info dictionary and referenced from the
document trailer. Latin-1-compatible strings are stored as PDF literal strings.
Other Unicode strings are stored as UTF-16BE hexadecimal strings.

## Binary Output

PaperForge can return the complete PDF as a binary:

```elixir
pdf_binary =
  PaperForge.to_binary(document)
```

This can be used in Phoenix or Plug responses:

```elixir
conn
|> put_resp_content_type("application/pdf")
|> put_resp_header(
  "content-disposition",
  ~s(attachment; filename="document.pdf")
)
|> send_resp(200, PaperForge.to_binary(document))
```

Write to disk:

```elixir
PaperForge.write(document, "document.pdf")
PaperForge.write!(document, "document.pdf")
```

## Architecture

PaperForge separates public drawing operations from low-level PDF objects.

```text
PaperForge
|-- Document
|   |-- object allocation
|   |-- font registry
|   |-- image registry
|   `-- metadata reference
|-- Page
|   `-- high-level drawing operations
|-- PageCompiler
|   |-- coordinate transforms
|   |-- font registration
|   |-- image registration
|   `-- resource dictionaries
|-- Graphics
|   |-- Text
|   |-- TextBox
|   |-- Line
|   |-- Rectangle
|   |-- Circle
|   `-- Image
|-- Serializer
|   `-- Elixir values to PDF syntax
`-- Writer
    |-- PDF header
    |-- indirect objects
    |-- cross-reference table
    |-- trailer
    `-- EOF marker
```

The generated PDF uses traditional cross-reference tables. Tests verify that
xref offsets point to the start of their corresponding indirect objects.

## Examples

Run the included examples:

```bash
mix run examples/hello.exs
mix run examples/graphics.exs
mix run examples/two_pages.exs
mix run examples/new_features.exs
mix run examples/png.exs
mix run examples/multilingual_layout.exs
mix run examples/complete_showcase.exs
```

Generated files are written under `tmp/`.

## Development

Clone the repository:

```bash
git clone git@github.com:Manuel1471/paper_forge.git
cd paper_forge
```

Run the test suite:

```bash
mix test
```

Compile with warnings treated as errors:

```bash
mix compile --warnings-as-errors
```

Format the source code:

```bash
mix format
```

Run all checks:

```bash
mix do format, compile --warnings-as-errors, test
```

Run the TrueType and Unicode benchmark script:

```bash
mix run benchmarks/truetype.exs
```

## Roadmap

### 0.4.x

- Better paragraph layout APIs
- Physical TrueType table subsetting for smaller `/FontFile2` streams

### Future

- OpenType CFF fonts
- PNG palette support
- Reusable Form XObjects
- HTML parsing
- CSS style resolution
- HTML/CSS layout engine
- Existing PDF parsing
- Incremental updates
- Digital signatures

## Project Status

PaperForge is experimental and currently intended for learning, testing, and
early integration.

The public API may change before version `1.0.0`.

## Contributing

Contributions, bug reports, architecture discussions, and PDF examples are
welcome.

Before opening a pull request:

```bash
mix format
mix compile --warnings-as-errors
mix test
```

## License

PaperForge is available under the terms specified in the [LICENSE](LICENSE).
