# PaperForge

PaperForge is a pure Elixir PDF generation engine. It builds PDF object graphs,
page content streams, resources, cross-reference tables, trailers, text layout,
vector graphics, metadata, and image XObjects directly in Elixir.

No browser, wkhtmltopdf, Chromium, ImageMagick, Ghostscript, or external
rendering service is required.

PaperForge is currently pre-1.0. The `0.5.x` API is usable, but some details may
still change while layout and image support mature.

## Why PaperForge?

- Generate PDFs without leaving Elixir or the BEAM.
- Avoid Chromium, Node.js, Python, native executables, and external rendering
  services.
- Build structured documents with automatic pagination.
- Render visible Unicode text with embedded TrueType fonts.
- Create reports, invoices, statements, contracts, and other business PDFs.
- Work with immutable Elixir data structures and process-safe APIs.

## Highlights

### Document Layout

- Unified block-based layout through `PaperForge.Flow`.
- Deterministic pagination with page-break and keep-together controls.
- Two-pass rendering with `PageContext` and total page counts.
- Named page templates with page size, orientation, margins, headers, and
  footers.
- Sections with metadata, template switching, destinations, and bookmarks.
- Multipage tables with repeated headers.
- Automatic heading destinations and outline bookmarks.
- Structured layout reports and debug reports.

### PDF Engine

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
- TrueType font-program deduplication by binary hash
- TrueType subsetting planning with composite glyph dependency resolution,
  table checksums, and `glyf`/`loca`/`hmtx`/`maxp` rebuild metadata
- TrueType PDF width and `/ToUnicode` subsetting for used glyphs
- Font-family registration with regular, bold, italic, and bold italic variants
- Document-level default font selection
- Visible Unicode text through Type 0 / CIDFontType2 fonts
- Identity-H encoding and `/ToUnicode` maps for embedded fonts
- Real TrueType metrics for width, wrapping, and alignment
- Internal links, named destinations, outlines, and bookmarks
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

## Which API Should I Use?

| Use case | Recommended API |
| --- | --- |
| Reports, invoices, statements, contracts | `PaperForge.Flow` |
| Automatic pagination | `PaperForge.layout/3` |
| Manual graphics and precise coordinates | `PaperForge.Page` |
| Existing applications using older flow APIs | `add_flow/4`, `add_table/4` |
| Debugging layout | `PaperForge.debug/2` |

## Installation

Add PaperForge to your dependencies:

```elixir
def deps do
  [
    {:paper_forge, "~> 0.5.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

To use the GitHub release directly:

```elixir
def deps do
  [
    {:paper_forge,
     github: "Manuel1471/paper_forge",
     tag: "v0.5.0"}
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

## Quick Start

```elixir
alias PaperForge.Flow

{document, report} =
  PaperForge.new(compress: true, pdf_version: "1.7")
  |> PaperForge.page_template(
    :default,
    size: :a4,
    margins: [top: 72, right: 54, bottom: 72, left: 54],
    header: "Quarterly Report",
    footer: "Page {page} of {total}"
  )
  |> PaperForge.layout(
    fn flow ->
      flow
      |> Flow.heading("Quarterly Report", level: 1)
      |> Flow.paragraph("""
      PaperForge measures, paginates, and renders document blocks automatically.
      """)
      |> Flow.list(
        ["Unified layout", "Automatic pagination", "Reusable templates"],
        type: :unordered
      )
      |> Flow.table(
        ["Metric", "Value"],
        [
          ["Revenue", "$120K"],
          ["Margin", "24%"]
        ],
        repeat_header: true
      )
    end,
    template: :default
  )

IO.inspect(report.pages, label: "Pages")
PaperForge.write!(document, "report.pdf")
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

## Low-level Page API

Use `PaperForge.Page` when you need manual graphics, exact coordinates, or a
lower-level drawing surface. New structured documents should usually start with
`PaperForge.Flow` and `PaperForge.layout/3`.

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
  the glyphs used by the document. The physical TrueType subsetting planner can
  resolve composite glyph dependencies and calculate table checksums, but final
  `/FontFile2` table reconstruction is still in progress.
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

## Unified Flow

`PaperForge.flow/2` builds a document from layout blocks instead of manual page
operations. The engine measures blocks, paginates them, calculates total pages,
and then renders the final pages.

```elixir
alias PaperForge.Flow

{document, report} =
  PaperForge.new()
  |> PaperForge.page_template(
    :report,
    size: :a4,
    margins: [top: 72, right: 54, bottom: 72, left: 54],
    header: "Quarterly report",
    footer: "Page {page} of {total}"
  )
  |> PaperForge.layout(
    fn flow ->
      flow
      |> Flow.heading("Quarterly report", level: 1)
      |> Flow.paragraph("Summary text that wraps and splits across pages.")
      |> Flow.list(["Revenue", "Expenses", "Cash"], type: :ordered)
      |> Flow.table(
        ["Metric", "Value"],
        [
          ["Revenue", "$120K"],
          ["Margin", "24%"]
        ],
        repeat_header: true
      )
      |> Flow.separator()
      |> Flow.page_break()
      |> Flow.section(:appendix, [title: "Appendix"], fn section ->
        section
        |> Flow.paragraph("Section content receives section metadata.")
      end)
    end,
    template: :report
  )
```

The report returned by `PaperForge.layout/3` contains page count, block count,
placements, warnings, and rendered page values. Placements include block ID,
block type, page number, coordinates, dimensions, and section metadata:

```elixir
{document, report} =
  PaperForge.layout(document, flow_function, template: :report)

report.pages
report.blocks
report.placements
```

Pagination options can be set on flow blocks:

```elixir
flow
|> Flow.heading("Appendix", page_break_before: true, keep_with_next: true)
|> Flow.paragraph("This paragraph should stay visually connected.")
|> Flow.separator(page_break_after: true)
```

Sections group related content under a stable section ID. A section can add a
title heading, start or end with page breaks, switch to a named page template,
and pass section metadata into `PageContext`:

```elixir
flow
|> Flow.section(:appendix, [title: "Appendix", template: :appendix], fn section ->
  section
  |> Flow.paragraph("Appendix content")
end)
```

Page templates can configure page geometry and reusable header/footer content:

```elixir
document =
  PaperForge.new()
  |> PaperForge.page_template(
    :appendix,
    size: :letter,
    orientation: :landscape,
    margins: [top: 60, right: 48, bottom: 60, left: 48],
    header: fn page, context ->
      Page.text(page, "Appendix", x: context.content_left, y: 24)
    end,
    footer: "Page {page} of {total}"
  )
```

Custom blocks receive the current `Page` and `PageContext`:

```elixir
Flow.custom(flow, fn page, context ->
  Page.text(
    page,
    "Page #{context.page_number} of #{context.total_pages}",
    x: context.content_left,
    y: context.content_top
  )
end, height: 24)
```

Debug reports summarize the generated document:

```elixir
PaperForge.debug(document,
  show_margins: true,
  show_blocks: true,
  show_page_breaks: true
)
```

Existing `Page`, `add_flow/4`, and `add_table/4` APIs remain supported for
compatibility. New applications should prefer `PaperForge.Flow` and
`PaperForge.layout/3`.

## Legacy Flow And Page-level APIs

The APIs in this section remain supported for compatibility. New applications
should prefer `PaperForge.Flow` and `PaperForge.layout/3`.

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

Get flow overflow information:

```elixir
{document, report} =
  PaperForge.layout_flow(
    PaperForge.new(),
    ["A long paragraph", "Another long paragraph"],
    [size: :letter, margins: 72],
    header: "Quarterly report",
    footer: "Generated by PaperForge",
    keep_together: true
  )

report.pages_added
report.overflow?
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

Create internal navigation:

```elixir
document =
  PaperForge.new()
  |> PaperForge.add_page(fn page ->
    page
    |> Page.destination(:intro, y: 720)
    |> Page.bookmark("Introduction", y: 720)
    |> Page.text("Introduction", x: 72, y: 720)
  end)
  |> PaperForge.add_page(fn page ->
    page
    |> Page.text("Back to intro", x: 72, y: 720)
    |> Page.link_to(:intro, x: 72, y: 700, width: 120, height: 24)
  end)
```

Add a paginated table with repeated headers:

```elixir
document =
  PaperForge.add_table(
    document,
    rows,
    [size: :a4, margins: 72],
    repeat_header: true,
    row_split: :keep
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
|-- Flow
|   `-- block-based document layout builder
|-- Layout
|   |-- Block
|   |-- Engine
|   `-- two-pass pagination and rendering
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
mix run examples/paper_forge_0_4_showcase.exs
mix run examples/paper_forge_0_5_showcase.exs
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

## Current Limitations

- The unified layout engine is the preferred rendering path for new
  applications, while page-level APIs remain available for compatibility.
- Rich text and inline mixed-style runs are not yet supported.
- Advanced widow and orphan control is not yet supported.
- Tables can continue across multiple pages, while individual rows are kept
  together. Content inside a single row or cell cannot yet be split across
  pages.
- Automatic table-of-contents generation is not yet supported.
- Advanced image cropping, fitting modes, and object positioning remain future
  work.
- Page-template inheritance and first, odd, even, or final-page template
  variants are not yet supported.
- Physical TrueType `/FontFile2` reconstruction is not enabled yet. PaperForge
  uses the subsetting planner foundation while embedding the original TrueType
  font program.

## Roadmap

### 0.6.x - Document Authoring

- Rich text and inline styles
- Physical TrueType subsetting
- Font fallback
- Automatic table of contents
- Advanced tables
- Advanced page templates
- Reusable document components

### 1.x - Production And Distributed Generation

- Streaming output
- Compiled templates
- Shared local caches
- Batch generation
- Telemetry
- Cancellation and timeouts
- Fault-tolerant job integration
- High-volume benchmarks

### 2.x - HTML And CSS

- HTML parsing
- CSS cascade and computed styles
- HTML/CSS to PaperForge Layout IR
- Paged-media layout
- Flexbox and advanced document styling

## Project Status

PaperForge is pre-1.0 and suitable for experimentation, prototypes, internal
tools, and early production evaluation.

The unified layout API is usable, but public API details may still change before
version `1.0.0`.

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
