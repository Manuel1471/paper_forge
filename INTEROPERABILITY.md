# Import, Forms, And PDF Interoperability

## Defensive parsing limits

The classic pure-Elixir PDF parser accepts only direct-object PDFs. Set input
limits when accepting PDFs from outside your own application:

```elixir
PaperForge.Interoperability.parse_pdf(binary,
  max_file_size: 100_000_000,
  max_objects: 500_000,
  max_depth: 100,
  max_stream_size: 50_000_000
)
```

The parser rejects the input before import when a configured limit is exceeded.
Encrypted PDFs and compressed object streams are intentionally unsupported.

PaperForge 1.4 keeps import and composition inside the BEAM. No browser,
native extension, command-line PDF tool, or external rendering service is
required at runtime.

## HTML And CSS

`PaperForge.Import.html/2` accepts HTML fragments and emits `PaperForge.Flow`
Layout IR. Supported document elements include headings, paragraphs, quotes,
preformatted text, ordered and unordered lists, tables, images, inline SVG,
and explicit page breaks.

The CSS subset supports element, class, and ID selectors plus colors,
backgrounds, font size, weight and style, alignment, dimensions, vertical
margins, and page breaks. Set `strict_css: true` to reject unsupported
properties instead of ignoring them.

```elixir
{:ok, flow} =
  PaperForge.Import.html("""
  <style>.lead { color: #0f766e; font-size: 14px; }</style>
  <h1>Imported report</h1>
  <p class="lead">This content uses the PaperForge layout engine.</p>
  """, strict_css: true)
```

This is a document-oriented subset, not a browser engine. JavaScript, remote
stylesheets, flexbox, grid, generated content, and arbitrary network resource
loading are not executed.

## Markdown

`PaperForge.Import.markdown/2` parses CommonMark through `EarmarkParser` and
maps headings, paragraphs, lists, quotes, code blocks, tables, links, and
emphasis to Layout IR.

## PDF Pages And Composition

`PaperForge.Interoperability.import_pages/3` selects one-based pages.
`compose/2` appends complete documents in order and deduplicates identical
font and XObject resources when possible. `resources/1` returns reusable font,
image, appearance, and embedded-file references.

```elixir
{:ok, cover} = PaperForge.Interoperability.import_pages(cover_pdf, [1])
{:ok, packet} = PaperForge.Interoperability.compose([cover, report, appendix_pdf])
PaperForge.write!(packet, "packet.pdf")
```

Binary parsing currently targets unencrypted PDFs with direct objects,
traditional cross-reference data, and ordinary page trees. Encrypted PDFs and
compressed object streams are rejected with structured errors. A source's
outlines, named destinations, and catalog-level AcroForm are not merged into
the destination catalog automatically.

## AcroForms

`PaperForge.AcroForm` creates standard text, checkbox, push-button, radio,
list, combo, and signature fields. It also imports and exports field data,
creates widget appearances, supports restricted sum/product/average actions,
and flattens current values into page content.

```elixir
document =
  document
  |> PaperForge.AcroForm.add_field(1, :text, "customer",
    rect: [72, 650, 280, 671],
    value: "Ada Lovelace",
    border_radius: 5,
    border_width: 0.75,
    border_color: "0.65 0.72 0.75")
  |> PaperForge.AcroForm.add_field(1, :checkbox, "approved",
    rect: [72, 610, 84, 622],
    value: true,
    border_radius: 3,
    check_color: "0.04 0.56 0.48")

data = PaperForge.AcroForm.export_data(document)
flat = PaperForge.AcroForm.flatten(document)
```

Signature fields reserve an interactive signature widget; cryptographic
signing remains the responsibility of `PaperForge.Signature`. XFA forms are
detected and rejected because XFA is a separate legacy runtime and document
model.

## Annotations

Use `PaperForge.Page.note/3`, `highlight/3`, `underline/3`, `strikeout/3`,
`stamp/3`, or `annotation/3` for common review workflows. Standard annotation
options include geometry, contents, color, author, subject, reply target, and
reply type. File attachments create real EmbeddedFile and Filespec objects.
