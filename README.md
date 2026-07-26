# PaperForge

PaperForge is a pure Elixir library for generating PDF documents directly, without browsers, operating-system binaries, or external rendering services.

It builds the PDF object graph, content streams, cross-reference table, and trailer entirely in Elixir.

> PaperForge is currently in early development. The `0.1.x` API may change while the document and graphics engines evolve.

## Why PaperForge?

Many PDF-generation tools work by converting HTML through Chromium, wkhtmltopdf, or another external application.

PaperForge takes a different approach:

```text
Elixir API
    ↓
Page and graphics operations
    ↓
PDF object graph
    ↓
Serializer
    ↓
Writer
    ↓
PDF binary
```

This provides direct control over the generated PDF structure and creates a foundation for future document layout, HTML/CSS rendering, parsing, and editing capabilities.

## Current features

PaperForge currently supports:

- Pure Elixir PDF generation
- Multiple pages
- A3, A4, A5, Letter, and Legal page sizes
- Custom page dimensions
- Portrait and landscape orientations
- Built-in Helvetica text
- Text size, position, and color
- Lines
- Rectangles
- Circles
- RGB and grayscale colors
- Basic document metadata
- PDF binary generation
- Direct file output
- Traditional PDF cross-reference tables

## Installation

PaperForge is currently under active development and may not yet be published on Hex.

Add it directly from GitHub:

```elixir
def deps do
  [
    {:paper_forge,
     github: "Manuel1471/paper_forge",
     branch: "main"}
  ]
end
```

Then install dependencies:

```bash
mix deps.get
```

After the first stable Hex release, installation will use:

```elixir
def deps do
  [
    {:paper_forge, "~> 0.1.0"}
  ]
end
```

## Quick start

```elixir
alias PaperForge.Color
alias PaperForge.Page

document =
  PaperForge.new()
  |> PaperForge.metadata(
    title: "PaperForge Example",
    author: "Manuel Garcia",
    subject: "Pure Elixir PDF generation",
    keywords: ["Elixir", "PDF"]
  )
  |> PaperForge.add_page(fn page ->
    page
    |> Page.text(
      "Hello from PaperForge",
      x: 72,
      y: 760,
      size: 28,
      color: Color.rgb255(35, 60, 120)
    )
    |> Page.line(
      x1: 72,
      y1: 740,
      x2: 520,
      y2: 740,
      width: 2,
      color: Color.rgb255(35, 60, 120)
    )
  end)

PaperForge.write!(document, "example.pdf")
```

## Drawing shapes

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

PaperForge approximates circles using four cubic Bézier curves because PDF does not provide a native circle operator.

## Multiple pages

```elixir
alias PaperForge.Page

document =
  PaperForge.new()
  |> PaperForge.add_page(fn page ->
    Page.text(
      page,
      "First page",
      x: 72,
      y: 750,
      size: 28
    )
  end)
  |> PaperForge.add_page(
    [size: :letter, orientation: :landscape],
    fn page ->
      Page.text(
        page,
        "Second page",
        x: 72,
        y: 500,
        size: 28
      )
    end
  )

PaperForge.write!(document, "multiple_pages.pdf")
```

## Page sizes

Supported page names:

```elixir
:a3
:a4
:a5
:letter
:legal
```

Example:

```elixir
PaperForge.add_page(
  document,
  [size: :letter, orientation: :landscape],
  fn page ->
    Page.text(page, "Landscape page", x: 72, y: 500)
  end
)
```

Custom page dimensions are also supported:

```elixir
Page.new(size: {500, 500})
```

All dimensions are expressed in PDF points.

```text
1 point = 1/72 inch
```

## Coordinate system

PaperForge currently uses the native PDF coordinate system.

```text
Y
↑
│
│
│
└────────────→ X
(0, 0)
```

The origin is located at the bottom-left corner of the page.

For an A4 page:

```text
width:  595.28 points
height: 841.89 points
```

Example:

```elixir
Page.text(
  page,
  "Near the top",
  x: 72,
  y: 760
)
```

A top-left coordinate abstraction is planned for a future release.

## Colors

### RGB using values from 0 to 1

```elixir
Color.rgb(1, 0, 0)
```

### RGB using values from 0 to 255

```elixir
Color.rgb255(255, 0, 0)
```

### Grayscale

```elixir
Color.gray(0.5)
Color.black()
Color.white()
```

## Metadata

```elixir
document =
  PaperForge.new()
  |> PaperForge.metadata(
    title: "Monthly Report",
    author: "Manuel Garcia",
    subject: "Project summary",
    keywords: ["report", "elixir", "pdf"],
    creator: "PaperForge",
    producer: "PaperForge"
  )
```

Metadata is written into the PDF Info dictionary and referenced from the document trailer.

## Binary output

PaperForge can return the complete PDF as a binary:

```elixir
pdf_binary =
  document
  |> PaperForge.to_binary()
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

## Architecture

PaperForge separates the public drawing API from the low-level PDF representation.

```text
PaperForge
│
├── Page
│   └── High-level drawing operations
│
├── Graphics
│   ├── Text
│   ├── Line
│   ├── Rectangle
│   └── Circle
│
├── Document
│   └── PDF object graph and object allocation
│
├── Object
│   └── Indirect PDF objects
│
├── Reference
│   └── References such as `3 0 R`
│
├── Stream
│   └── Stream dictionaries and binary data
│
├── Serializer
│   └── Elixir values to PDF syntax
│
└── Writer
    ├── PDF header
    ├── Indirect objects
    ├── Cross-reference table
    ├── Trailer
    └── EOF marker
```

A page operation follows this pipeline:

```text
Page.text/3
    ↓
PDF text operators
    ↓
Page content stream
    ↓
Indirect PDF object
    ↓
Serializer
    ↓
Writer
    ↓
PDF bytes
```

## PDF structure

PaperForge generates PDFs using a graph of indirect objects.

```text
Trailer
└── Catalog
    └── Page tree
        ├── Page
        │   ├── Resources
        │   └── Content stream
        └── Page
            ├── Resources
            └── Content stream
```

Objects are connected through references such as:

```pdf
3 0 R
```

This means:

```text
object number: 3
generation:    0
type:          indirect reference
```

## Development

Clone the repository:

```bash
git clone git@github.com:Manuel1471/paper_forge.git
cd paper_forge
```

Install local development tools:

```bash
mix local.hex --force
mix local.rebar --force
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

Generate the graphics example:

```bash
mix run examples/graphics.exs
open tmp/paper_forge_0_1.pdf
```

## Roadmap

### 0.2.0

- Text measurement
- Horizontal text alignment
- More built-in PDF fonts
- Stream compression
- JPEG image support
- PNG image support
- Top-left coordinate helpers
- Improved metadata encoding

### 0.3.0

- Paragraph layout
- Automatic line wrapping
- Margins
- Vertical content flow
- Automatic page breaks
- Basic tables

### Future

- TrueType and OpenType fonts
- Unicode text
- PNG palette support
- Reusable Form XObjects
- Links and annotations
- HTML parsing
- CSS style resolution
- HTML/CSS layout engine
- Existing PDF parsing
- Incremental updates
- Digital signatures

## Project status

PaperForge is experimental and currently intended for learning, testing, and early integration.

The public API may change before version `1.0.0`.

## Contributing

Contributions, bug reports, architecture discussions, and PDF examples are welcome.

Before opening a pull request:

```bash
mix format
mix compile --warnings-as-errors
mix test
```

## License

PaperForge is available under the terms specified in the [LICENSE](license.html).
