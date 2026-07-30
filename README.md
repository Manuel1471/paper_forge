# PaperForge

PaperForge is a pure Elixir PDF generation engine. It builds PDF object graphs,
page content streams, resources, cross-reference tables, trailers, text layout,
vector graphics, metadata, and image XObjects directly in Elixir.

No browser, wkhtmltopdf, Chromium, ImageMagick, Ghostscript, or external
rendering service is required.

PaperForge 1.0 provides a stable public API for pure-Elixir PDF authoring.
Documented public modules follow Semantic Versioning throughout the 1.x series.

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
- Multipage tables with wrapped cells, content-aware row heights, repeated
  headers, and configurable row splitting.
- Automatic heading destinations and outline bookmarks.
- Structured layout reports and debug reports.
- Rich text runs, document styles, reusable components, and automatic tables
  of contents with linked page numbers.
- Template inheritance, grid layouts, and multi-column document sections.
- Widow/orphan controls, optional hyphenation, and per-block measurement diagnostics.
- Native bar charts and XML-parsed SVG vectors with paths, Bézier curves,
  polygons, groups, transforms, `viewBox`, clipping, and cascading styles.
- Vector QR codes and Interleaved 2 of 5 barcodes.
- Embedded document attachments, text-note annotations, highlights,
  bottom-of-page footnotes, and automatic endnotes.
- Page-aware internal cross-references and positioned custom drawing blocks.

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
  limits, justification, and `:clip | :ellipsis | :continue | :error` overflow
- The 14 standard PDF Type 1 fonts
- Embedded TrueType fonts loaded from paths or binaries
- TrueType font-program deduplication by binary hash
- Physical TrueType subsetting with composite glyph dependency resolution,
  checksum recalculation, and `glyf`/`loca`/`hmtx`/`maxp` reconstruction
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
- JPEG EXIF orientation and aspect-aware `:contain`/`:cover` fitting
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
    {:paper_forge, "~> 1.0"}
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
     tag: "v1.0.0"}
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

## Document Authoring

`0.6.0` adds a higher-level authoring layer on top of `PaperForge.Flow`.
Register shared styles, reusable components, and inherited page templates once;
then compose documents from declarative blocks.

```elixir
alias PaperForge.Flow

document =
  PaperForge.new()
  |> PaperForge.style(:body, size: 10, line_height: 14)
  |> PaperForge.component(:customer, fn assigns ->
    Flow.new()
    |> Flow.rich_text([
      {assigns.name, [weight: :bold]},
      {"\n#{assigns.address}", [size: 9]}
    ])
  end)
  |> PaperForge.page_template(:base, size: :a4, margins: 54, footer: "Page {page} of {total}")
  |> PaperForge.page_template(:invoice, extends: :base, header: "Invoice")

{document, _report} =
  PaperForge.layout(document, fn flow ->
    flow
    |> Flow.table_of_contents()
    |> Flow.heading("Invoice")
    |> Flow.component(:customer, %{name: "Acme", address: "Monterrey, MX"})
    |> Flow.grid(2, ["Subtotal\n$1,200", "Due\n30 days"], cell_height: 60)
    |> Flow.columns(2, ["Terms and conditions...", "Payment instructions..."])
  end, template: :invoice)
```

Available authoring blocks include `rich_text/3`, `table_of_contents/2`,
`reference/3`, `component/4`, `grid/4`, and `columns/4`. Tables accept explicit
`:column_widths`, `:header_fill_color`, `:header_color`, and
`:stripe_fill_color` options. See
[`paper_forge_0_6_authoring.exs`](examples/paper_forge_0_6_authoring.exs) and
[`linkedin_document_showcase.exs`](examples/linkedin_document_showcase.exs) for
complete documents.

Images support `fit: :fill | :contain | :cover`, horizontal and vertical
alignment, and `focal_point: {x, y}`. Numbered images and tables create stable
destinations for page-aware references.

The complete release example is
[`paper_forge_0_6_complete.exs`](examples/paper_forge_0_6_complete.exs). It
combines navigation, advanced tables, footnotes, endnotes, charts, SVG, QR,
barcode, attachments, components, and custom report panels in one PDF.

Page-aware navigation is resolved with bounded multi-pass pagination:

```elixir
flow
|> Flow.table_of_contents(title: "Contents")
|> Flow.heading("Financial results", destination: :financial_results)
|> Flow.reference(:financial_results, prefix: "Financial results begin on page ")
```

Custom blocks receive their measured `block_x`, `block_y`, `block_width`, and
`block_height` in `PageContext`, so bespoke report panels can participate in
normal flow without hard-coding page coordinates.

### Typography And Report Visuals

Paragraph blocks can request hyphenation and minimum line counts around page
breaks. Layout reports expose `:measurements` for each placed block.

```elixir
flow
|> Flow.paragraph(long_copy, hyphenate: true, min_lines_at_top: 2, min_lines_at_bottom: 2)
|> Flow.chart([{"Q1", 418}, {"Q2", 432}, {"Q3", 451}], height: 140)
|> Flow.svg("<svg><rect x='0' y='0' width='80' height='30' fill='#0077b5'/></svg>", height: 40)
|> Flow.qr_code("https://example.com/pay/INV-2048", width: 96, height: 96)
|> Flow.barcode("20481234", width: 180, height: 64)
```

### Advanced Tables And Notes

Table rows are measured from their wrapped cell content. `:keep` moves an
oversized row to a fresh page, `:split` continues cell content across pages, and
`:error` raises `PaperForge.TableError` when a row cannot fit.

Use `Flow.cell/2` for composable cells with `:colspan`, `:rowspan`, `:valign`,
per-cell colors, per-side borders, and nested flow blocks.

```elixir
flow
|> Flow.table(
  ["Item", "Description"],
  rows,
  column_widths: [110, 340],
  repeat_header: true,
  row_split: :split,
  cell_line_height: 12
)
|> Flow.footnote("Values are unaudited and shown in USD.")
|> Flow.endnotes([])
```

Footnotes reserve space at the bottom of the current flow page, number
themselves when the number is omitted, append a visible call marker to the
preceding paragraph, rich-text block, heading, or final table cell, and continue
on another page when necessary. Pass `marker: false` to author the call marker
manually. `Flow.endnotes/3` emits the collected notes as a document section.

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
- PaperForge physically subsets embedded TrueType programs while preserving
  original glyph identifiers, and rebuilds affected `glyf`, `loca`, `hmtx`, and
  `maxp` tables with valid checksums.
- A missing glyph raises `PaperForge.FontError` unless a registered full-run
  fallback is configured through `PaperForge.font_fallback/3`.

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
mix run examples/paper_forge_0_6_authoring.exs
mix run examples/linkedin_document_showcase.exs
mix run examples/paper_forge_0_6_complete.exs
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

## Scope Boundaries

- The unified layout engine is the preferred rendering path for new
  applications, while page-level APIs remain available for compatibility.
- PaperForge 1.0 targets standard PDF authoring and Unicode text supported by
  embedded TrueType fonts. Complex-script shaping and bidirectional layout are
  outside the 1.0 compatibility contract.
- Widow and orphan control uses configurable minimum line counts. Optional
  hyphenation deterministically breaks overlong words rather than consulting
  language dictionaries.
- PaperForge emits standard PDF 1.4 through 1.7 files. PDF/A output profiles
  are outside the 1.0 compatibility contract.

## Performance Envelope

`mix run benchmarks/document_scale.exs` measures a 5,000-row report. On the
reference development machine it generated 179 pages in about 805 ms, serialized
in about 62 ms, produced a 617 KB PDF, and increased total BEAM memory by about
67 MB. Treat these values as a reproducible baseline, not fixed assertions.

See [`API.md`](API.md) for the public compatibility policy and
[`MIGRATING.md`](MIGRATING.md) for the 0.6-to-1.0 upgrade guide.

## Production Hardening

- `PaperForge.validate/1` returns structured validation reports and issue codes.
- `PaperForge.validate!/1` raises `PaperForge.ValidationError` on corrupt
  document graphs.
- Serialization validates required objects, indirect references, page-tree
  counts, object identity, and PDF versions.
- Identical immutable documents produce byte-for-byte identical output.
- Corrupted-image fuzz tests exercise deterministic error handling.
- Internal conformance tests verify PDF headers, xref offsets, and EOF markers.
- The compatibility test uses `pdfinfo` when it is available.

See [`MIGRATING.md`](MIGRATING.md) for the stable 1.0 compatibility contract.

## Future Enhancements

These ideas are not required by, or promised as part of, the stable 1.0 API.
They describe possible directions for later minor and major releases.

### International Typography

- Connect complex-script shaping, bidirectional paragraph layout, and
  glyph-level font fallback after `harfbuzz_ex` exposes numeric glyph IDs.
  PaperForge will consume that public API without adding a private NIF or an
  installation-time native build.
- Add language dictionaries for discretionary hyphenation. The current
  `hyphenate: true` option only breaks overlong words deterministically.
- Establish PDF/A output profiles. VeraPDF remains an optional external
  validator and is not required to install or run PaperForge.

### Declarative Authoring

- Introduce a versioned `.paperforge` template format backed by a safe,
  declarative document model.
- Support validated variables, loops, conditions, reusable components, and
  resource references without evaluating arbitrary Elixir code.
- Use the same format as the interchange contract for a future visual document
  designer.

### Production And Distributed Generation

- Streaming output
- Compiled templates
- Shared local caches
- Batch generation
- Telemetry
- Cancellation and timeouts
- Fault-tolerant job integration
- High-volume benchmarks

### HTML And CSS

- HTML parsing
- CSS cascade and computed styles
- HTML/CSS to PaperForge Layout IR
- Paged-media layout
- Flexbox and advanced document styling

## Project Status

PaperForge 1.0 is the first stable release and is suitable for production PDF
authoring within the documented scope. Public APIs listed in [`API.md`](API.md)
follow Semantic Versioning throughout the 1.x series.

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
