# Changelog

All notable changes to PaperForge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-07-29

### Added

#### Authoring and layout

- Added rich-text runs, named styles, reusable components, inherited templates,
  grids, multi-column sections, and measured custom blocks.
- Added linked tables of contents and page-aware cross-references using bounded
  multi-pass pagination.
- Added widow/orphan controls, optional long-word hyphenation, and placement
  diagnostics.
- Added bottom-of-page footnotes with automatic numbering and continuation,
  plus automatic endnote sections.
- Added automatic footnote call markers for preceding paragraphs, headings,
  rich-text blocks, and final table cells.
- Added first, last, odd, and even header/footer variants plus independent
  section page counters.
- Added justified text and explicit `:clip`, `:ellipsis`, `:continue`, and
  `:error` overflow strategies.
- Added configurable multilevel TOC formatting and numbered figure/table
  destinations with page-aware references.

#### Advanced tables

- Added content-aware row heights and text wrapping inside cells.
- Added repeated headers and `row_split: :keep | :split | :error`.
- Added cell and row continuation across pages without dropping content.
- Added explicit column widths, header colors, alignment, and striped rows.
- Added composable cells with `colspan`, `rowspan`, vertical alignment,
  per-side borders, colors, and nested block content.

#### Fonts, graphics, and PDF features

- Added physical TrueType subsetting with composite glyph retention and
  reconstruction of `glyf`, `loca`, `hmtx`, and `maxp`.
- Added font-program deduplication and primary-font fallback selection.
- Added vector QR codes, Interleaved 2 of 5 barcodes, native bar charts, and an
  XML-based SVG renderer supporting paths, Bézier curves, polygons, ellipses,
  groups, transforms, `viewBox`, clipping, and inherited styles.
- Added image `:contain`/`:cover` fitting, focal positioning, PDF clipping, and
  automatic JPEG EXIF orientation.
- Added embedded file attachments, text-note annotations, and highlights.

#### Production hardening

- Added `PaperForge.validate/1` and `PaperForge.validate!/1`.
- Added `PaperForge.ValidationError` with machine-readable issue maps.
- Added pre-serialization checks for catalog/page-tree integrity, object
  identity, dangling references, page counts, and PDF versions.
- Added byte-for-byte determinism tests.
- Added corrupted-image fuzz coverage and internal xref/EOF conformance checks.
- Added optional `pdfinfo` compatibility validation.
- Added optional `qpdf --check` and VeraPDF CI checks.
- Added a 5,000-row memory and runtime benchmark.
- Added `API.md` with the developing `1.x` compatibility and deprecation policy.
- Added `MIGRATING.md` for the developing 1.0 compatibility contract.

### Changed

- Changed the package version to `0.6.0`.
- Changed navigation materialization to iterate until page labels stabilize.
- Changed linked flow paragraphs, table-of-contents entries, and cross-references
  to emit real PDF `/Link` annotations targeting their named destinations.
- Changed bar-chart geometry to reserve consistent space above the plot for
  value labels, including the tallest bar.
- Increased the default footnote separator clearance so the rule cannot touch
  the first line of note text.
- Rebuilt the invoice and investor-report examples with production-oriented
  visual layouts.

### Examples and tests

- Added `examples/paper_forge_0_6_complete.exs`, a complete release showcase.
- Added polished invoice and investor-report examples.
- Added integration coverage for authoring, navigation, advanced tables,
  footnotes, graphics, attachments, annotations, and physical font subsets.

### Known limitations

- Complex-script shaping, advanced bidirectional layout, and glyph-level font
  fallback are waiting for `harfbuzz_ex` to expose numeric glyph IDs. PaperForge
  will consume that API without introducing a private NIF or manual native
  installation steps; the behavior is intentionally not simulated.
- Language-aware dictionary hyphenation is not included. `hyphenate: true`
  deterministically splits only words that cannot fit on a line.
- PDF/A output profiles are not yet emitted. Optional VeraPDF checks are skipped
  when the validator is unavailable and never affect package installation.

## [0.5.0] - 2026-07-27

### Added

#### Unified document layout

- Added `PaperForge.Layout.Block` as the common block representation.
- Added stable block identifiers for layout debugging and reports.
- Added `PaperForge.Flow` as the builder for unified layout documents.
- Added `PaperForge.flow/2` for rendering unified document flows.
- Added `PaperForge.layout/3` for rendering flows with layout reports.
- Added an internal layout engine with deterministic pagination and rendering.
- Added block measurement before rendering.
- Added block splitting for paragraphs, lists, and tables.
- Added page-break blocks.
- Added `page_break_before` and `page_break_after` block options.
- Added `keep_with_next` support for headings and related content.
- Added minimum remaining-height checks before heading placement.
- Added keep-together containers.
- Added oversized-block detection to prevent infinite pagination loops.
- Added custom blocks that receive `Page` and `PageContext`.
- Added layout reports with page count, block count, placements, warnings, and
  rendered pages.
- Added placement reports containing block ID, block type, page number,
  coordinates, dimensions, and section metadata.
- Added structured layout debug reports through `PaperForge.debug/2`.

#### Flow API

- Added `PaperForge.Flow.heading/3`.
- Added `PaperForge.Flow.paragraph/3`.
- Added `PaperForge.Flow.image/3`.
- Added `PaperForge.Flow.table/4`.
- Added `PaperForge.Flow.list/3`.
- Added `PaperForge.Flow.spacer/2`.
- Added `PaperForge.Flow.separator/2`.
- Added `PaperForge.Flow.page_break/1`.
- Added `PaperForge.Flow.keep_together/2`.
- Added `PaperForge.Flow.custom/3`.
- Added `PaperForge.Flow.section/4`.

#### Two-pass rendering

- Added `PaperForge.PageContext`.
- Added page number and total page count in layout context.
- Added content bounds and section metadata in layout context.
- Added late header/footer rendering after total pages are known.
- Added `Page {page} of {total}` footer placeholders for string footers.
- Added automatic named destinations for rendered headings.
- Added outline bookmark generation from rendered headings.
- Added duplicate destination validation before rendering.
- Added unresolved internal link-target validation for flow block link metadata.

#### Sections and templates

- Added flow sections with IDs, titles, template selection, page-break behavior,
  destinations, bookmarks, and section metadata.
- Added `PaperForge.page_template/3`.
- Added named page template registration on documents.
- Added named page templates with page size, orientation, margins, headers, and
  footers.
- Added template resolution in `PaperForge.layout/3` and section template
  switching inside flow documents.
- Added reserved header and footer regions through page margins and content
  bounds.
- Added dynamic header and footer callbacks receiving `PaperForge.PageContext`.
- Added `PaperForge.PageTemplateError` for missing templates.

#### Layout blocks

- Added heading blocks with levels.
- Added paragraph blocks with wrapping and page splitting.
- Added image blocks with `width: :content`, fixed width/height, alignment, and
  captions.
- Added multipage table blocks with repeated headers.
- Added deterministic table continuation across pages.
- Added list blocks with ordered and unordered markers.
- Added spacer and separator blocks.

#### Structured errors

- Added `PaperForge.LayoutError`.
- Added `PaperForge.TableError`.
- Added `PaperForge.NavigationError`.
- Added `PaperForge.PageTemplateError`.
- Added structured metadata fields for layout, table, navigation, and template
  failures.

#### Tests

- Added tests for stable block IDs.
- Added tests for flow builder APIs.
- Added tests for unified flow rendering, headings, paragraphs, lists, sections,
  page breaks, tables, images, templates, debug reports, and bookmarks.
- Added tests for pagination controls, section template switching, placement
  reports, duplicate destinations, unresolved link targets, and oversized-block
  diagnostics.

### Changed

- Changed the package version to `0.5.0`.
- Updated README for the unified layout API.

### Compatibility

- Existing `Page`, `add_flow/4`, and `add_table/4` APIs remain supported.
- New applications should prefer `PaperForge.Flow` and `PaperForge.layout/3`.
- Legacy APIs are not removed or formally deprecated in this release.

### Limitations

- The 0.5.0 layout engine is the new unified rendering path. Existing page-level
  APIs remain available for compatibility, but new applications should prefer
  `PaperForge.Flow` and `PaperForge.layout/3`.
- Rich text and inline mixed-style runs are not yet supported.
- Advanced widow and orphan control is not yet supported.
- Table rows can continue across pages as grouped units, but content inside an
  individual row or cell cannot yet be split across pages.
- Automatic table-of-contents generation is not yet supported.
- Advanced image cropping, fitting modes, and object positioning remain future
  work.
- Page-template inheritance and advanced first, odd, even, or final-page
  variants are not yet supported.
- Physical TrueType `/FontFile2` reconstruction is not enabled yet. PaperForge
  continues to use the subsetting planner foundation introduced in 0.4.0 while
  embedding the original TrueType font program.

## [0.4.0] - 2026-07-27

### Added

#### TrueType subsetting foundation

- Added TrueType font-program deduplication by SHA-256 binary hash.
- Added parsing of `loca` offsets and `head.indexToLocFormat`.
- Added preservation of raw TrueType table data for physical subsetting work.
- Added `PaperForge.Fonts.TrueType.glyph_dependencies/2`.
- Added recursive composite glyph dependency expansion.
- Added `PaperForge.Fonts.TrueType.Subsetter`.
- Added physical subsetting plans that include:
    - Requested glyphs
    - `.notdef`
    - Composite glyph dependencies
    - Tables that must be rebuilt: `glyf`, `loca`, `hmtx`, and `maxp`
    - TrueType table checksums
    - Font binary hashes
- Added TrueType checksum calculation with four-byte padding.

#### Advanced layout

- Added `PaperForge.layout_flow/4` for flow layout with a report.
- Added flow reports with `:pages_added`, `:blocks`, and `:overflow?`.
- Added `:keep_together` support for flowed blocks.
- Added `:header` and `:footer` support for flowed pages.
- Added `PaperForge.add_table/4` for paginated tables.
- Added repeating table headers across generated pages.
- Added `row_split: :keep` validation for table row splitting policy.
- Added `PaperForge.Page.list/3` for ordered and unordered lists.

#### PDF navigation

- Added named destinations.
- Added internal document links through `PaperForge.Page.link_to/3`.
- Added page destinations through `PaperForge.Page.destination/3`.
- Added outlines and bookmarks through `PaperForge.Page.bookmark/3`.
- Added catalog `/Names` trees for named destinations.
- Added catalog `/Outlines` trees and linked outline items.
- Added internal link annotations using `/Dest`.

#### Tests

- Added tests for TrueType font-program deduplication by binary hash.
- Added tests for TrueType subsetting plans and checksum calculation.
- Added tests for named destinations, internal links, and outline bookmarks.
- Added tests for ordered and unordered lists.
- Added tests for flow reports, headers, footers, and keep-together behavior.
- Added tests for paginated tables with repeated headers.

### Changed

- Changed the package version to `0.4.0`.
- Updated the README for the 0.4.0 subsetting, layout, and navigation work.

### Limitations

- Final physical `/FontFile2` reconstruction is still in progress. The new
  subsetting planner resolves dependencies and checksum data, but PaperForge
  still embeds the original font program when generating PDFs.
- Table row splitting currently supports keeping rows together with
  `row_split: :keep`; splitting a single row across pages is not implemented
  yet.
- Additional annotation types beyond URI links and internal links are still
  planned.

## [0.3.0] - 2026-07-26

### Added

#### Embedded TrueType fonts

- Added `PaperForge.register_font/3` for registering embedded TrueType fonts.
- Added support for loading TrueType fonts from file paths.
- Added support for loading TrueType fonts from in-memory binaries.
- Added `PaperForge.Fonts.TrueType` for parsing compatible `.ttf` files.
- Added validation for unsupported OpenType CFF fonts.
- Added validation for invalid or truncated TrueType files.
- Added parsing for required TrueType tables:
    - `head`
    - `hhea`
    - `maxp`
    - `hmtx`
    - `cmap`
    - `name`
    - `OS/2`
    - `post`
    - `loca`
    - `glyf`
- Added extraction of:
    - Units per em
    - Glyph count
    - Unicode-to-glyph mappings
    - Glyph widths
    - Font bounding box
    - Ascent
    - Descent
    - Cap height
    - Italic angle
    - PostScript font name
- Added support for Unicode `cmap` format 4 and format 12 subtables.
- Added embedded PDF Type 0 fonts with CIDFontType2 descendants.
- Added `/Identity-H` encoding for embedded TrueType fonts.
- Added `/FontFile2` streams for embedded TrueType font programs.
- Added `/FontDescriptor` dictionaries for embedded TrueType fonts.
- Added CID width arrays from real TrueType metrics.
- Added prefixed embedded font names such as `PF0001+FontName`.
- Added subsetting of generated CID width arrays to glyphs used by the
  document.
- Added subsetting of generated `/ToUnicode` CMaps to glyphs used by the
  document.
- Added `PaperForge.register_font_family/3` for TrueType font families.
- Added support for `:regular`, `:bold`, `:italic`, and `:bold_italic`
  TrueType family variants.
- Added document-level default font selection through `PaperForge.default_font/2`.
- Added `:default_font` support to `PaperForge.new/1`.

#### Unicode visible text

- Added visible Unicode text rendering through registered TrueType fonts.
- Added glyph-id text encoding for embedded Type 0 fonts.
- Added `/ToUnicode` CMaps for registered TrueType fonts.
- Added Unicode extraction/search support for generated embedded-font text.
- Added `PaperForge.FontError` for font registration, parsing, and glyph
  errors.
- Added clear errors for unregistered font keys.
- Added clear errors when a registered TrueType font does not contain a
  required glyph.
- Added support for Spanish accents, `ñ`, `ü`, inverted punctuation,
  typographic symbols, Greek, and Cyrillic when the registered font contains
  those glyphs.

#### Text metrics

- Added TrueType-backed width measurement in `PaperForge.TextMetrics`.
- Updated text alignment to use real TrueType glyph widths when a registered
  font is used.
- Updated text wrapping and text boxes to use registered TrueType metrics.
- Updated page compilation to pass registered font instances into text
  measurement and rendering.

#### Tests

- Added unit tests for TrueType parsing and metrics.
- Added unit tests for Unicode `cmap` glyph resolution.
- Added unit tests for Spanish, symbol, Greek, and Cyrillic glyph coverage.
- Added unit tests for truncated and unsupported font files.
- Added integration tests for TrueType registration from paths and binaries.
- Added integration tests for TrueType font deduplication by registered key.
- Added structural PDF tests for `/Type0`, `/CIDFontType2`, `/FontFile2`,
  `/Identity-H`, and `/ToUnicode`.
- Added tests for TrueType-backed text measurement.
- Added tests for unregistered fonts and missing glyph errors.
- Added `benchmarks/truetype.exs` for TrueType registration, text measurement,
  multiline rendering, and multilingual PDF generation.
- Added tests for TrueType width and `/ToUnicode` subsetting.
- Added tests for default fonts and font-family variant resolution.
- Added PDF compatibility smoke tests for multilingual documents, xref markers,
  `startxref`, EOF markers, and `/ToUnicode`.

#### Document layout

- Added `PaperForge.add_flow/4` for vertical content flow.
- Added automatic page breaks for flowed text blocks.
- Added `PaperForge.Page.paragraph/3` as a paragraph-oriented text-box alias.
- Added `PaperForge.Page.table/3` for basic table rendering.
- Added `PaperForge.Page.link/3` for URI link annotations.
- Added PDF `/Annot` link dictionaries with URI actions.
- Added page `/Annots` arrays when a page contains link annotations.
- Added tests for tables, links, vertical flow, and automatic page breaks.

### Changed

- Changed unknown non-standard font keys to raise `PaperForge.FontError`
  instead of a generic `ArgumentError`.
- Changed the package version to `0.3.0`.
- Updated the README to document embedded TrueType fonts, visible Unicode text,
  font families, default fonts, vertical flow, tables, links, and current font
  limitations.

### Limitations

- Physical TrueType table reconstruction is not implemented yet; generated PDF
  width arrays and `/ToUnicode` maps are subset to used glyphs, but the full
  `.ttf` program is still embedded in `/FontFile2`.
- OpenType CFF (`OTTO`) and TrueType Collection (`.ttc`) fonts are not
  supported yet.
- Complex shaping for scripts such as Arabic and Devanagari is not performed
  yet.

## [0.2.0] - 2026-07-26

### Added

#### Document configuration

- Added document-level configuration through `PaperForge.new/1`.
- Added the `:compress` document option.
- Enabled Flate stream compression by default.
- Added support for disabling compression with `PaperForge.new(compress: false)`.
- Added the `:pdf_version` document option with `"1.7"` as the default.
- Added validation for unsupported document options.
- Added validation for invalid compression and PDF version values.

#### Stream compression

- Added `PaperForge.Compression`.
- Added stream compression using the PDF `/FlateDecode` filter.
- Added support for streams with zero, one, or multiple filters.
- Added automatic insertion of the `/Filter` entry in stream dictionaries.
- Added compression support for page content streams.
- Preserved JPEG image data without recompressing it.
- Added tests that decompress Flate streams and verify their actual commands.

#### Fonts

- Added a built-in font registry.
- Added automatic reuse of fonts already registered in a document.
- Added on-demand font registration when pages are compiled.
- Added sequential font resource names such as `/F1`, `/F2`, and `/F3`.
- Added support for the 14 standard PDF Type 1 fonts:
    - Helvetica
    - Helvetica Bold
    - Helvetica Oblique
    - Helvetica Bold Oblique
    - Times Roman
    - Times Bold
    - Times Italic
    - Times Bold Italic
    - Courier
    - Courier Bold
    - Courier Oblique
    - Courier Bold Oblique
    - Symbol
    - Zapf Dingbats
- Added font family and style metadata.
- Added support for WinAnsi and built-in font encodings.
- Added `PaperForge.Font.definition_to_dictionary/1`.
- Added built-in font metrics.
- Added text-width measurement through `PaperForge.TextMetrics`.
- Added tests for font registration, font reuse, unsupported fonts, and
  consecutive font resource names without relying on fixed object IDs.

#### Text layout

- Added text alignment:
    - Left
    - Center
    - Right
- Added optional text width for alignment calculations.
- Added automatic text measurement using built-in font metrics.
- Added `PaperForge.TextWrapper`.
- Added automatic word wrapping.
- Added support for explicit newline characters.
- Added configurable line height.
- Added long-word splitting when a word exceeds the available width.
- Added `PaperForge.Graphics.TextBox`.
- Added multiline text boxes.
- Added optional text-box height limits.
- Added line-count and overflow information from text-box layout.
- Added support for text-box alignment.
- Added support for text-box fill color.
- Added support for selecting built-in fonts by atom.

#### Page coordinates and margins

- Added `PaperForge.Coordinates`.
- Added support for bottom-left page coordinates.
- Added support for top-left page coordinates.
- Added per-operation origin overrides.
- Added coordinate conversion for:
    - Text
    - Text boxes
    - Lines
    - Rectangles
    - Circles
    - Images
- Added `PaperForge.Margins`.
- Added uniform page margins.
- Added independent top, right, bottom, and left margins.
- Added margin validation against page dimensions.
- Added page content helpers:
    - `PaperForge.Page.content_width/1`
    - `PaperForge.Page.content_height/1`
    - `PaperForge.Page.content_left/1`
    - `PaperForge.Page.content_top/1`
    - `PaperForge.Page.content_bottom/1`
- Added automatic text positioning based on page margins when `:x` or `:y`
  are omitted.

#### Images

- Added JPEG image support.
- Added support for non-interlaced 8-bit grayscale, RGB, grayscale-alpha,
  and RGBA PNG images.
- Added JPEG signature validation.
- Added PNG signature validation.
- Added JPEG marker parsing without decoding image pixels.
- Added PNG IHDR and IDAT parsing without decoding image pixels.
- Added extraction of:
    - Width
    - Height
    - Bits per component
    - Number of color components
    - Color space
- Added support for:
    - Grayscale JPEG images
    - RGB JPEG images
    - CMYK JPEG images
    - Grayscale PNG images
    - RGB PNG images
    - Grayscale PNG images with alpha
    - RGBA PNG images
- Added PDF image XObjects using `/DCTDecode`.
- Added PNG image XObjects using `/FlateDecode` and PNG predictor decode
  parameters.
- Added PNG transparency support using PDF soft masks (`/SMask`).
- Optimized PNG parsing to avoid unnecessary per-pixel reconstruction when
  the PNG can be inserted directly into the PDF.
- Added CMYK decode arrays for compatible JPEG images.
- Added `PaperForge.Image`.
- Added `PaperForge.ImageRegistry`.
- Added SHA-256-based image deduplication.
- Added sequential image resource names such as `/Im1` and `/Im2`.
- Added image loading from:
    - File paths
    - JPEG binaries
    - PNG binaries
- Added automatic aspect-ratio preservation.
- Added image sizing using:
    - Original dimensions
    - Width only
    - Height only
    - Explicit width and height
- Added `PaperForge.Graphics.Image`.
- Added PDF image drawing using the `cm` and `Do` operators.
- Added page-level image operations through `PaperForge.Page.image/3`.
- Added tests for RGB, grayscale, CMYK, invalid, truncated, duplicated, and
  distinct JPEG image handling.
- Added tests for RGB, grayscale, grayscale-alpha, RGBA, invalid, truncated,
  deduplicated, and unsupported PNG image handling.
- Added PNG parsing benchmarks and large-image tests.

#### Page resources

- Added `PaperForge.PageResources`.
- Added centralized page resource management.
- Added automatic font resource dictionaries.
- Added automatic image XObject dictionaries.
- Added resource deduplication within pages.
- Added support for pages containing multiple fonts and images.

#### Metadata and string encoding

- Added `PaperForge.StringEncoding`.
- Added automatic PDF string encoding selection.
- Added literal PDF strings for compatible text.
- Added UTF-16BE encoding for Unicode metadata.
- Added Unicode support for:
    - Title
    - Author
    - Subject
    - Keywords
    - Creator
    - Producer
- Added creation-date metadata.
- Added modification-date metadata.
- Added PDF date serialization for:
    - `DateTime`
    - `NaiveDateTime`
- Added timezone-offset serialization for `DateTime` metadata.
- Added metadata option validation.
- Added omission of empty metadata values.
- Added tests for Latin-1 and UTF-16BE metadata serialization.

#### Public API

- Added `PaperForge.new/1`.
- Added page creation with options through `PaperForge.add_page/3`.
- Added support for passing an existing page to `PaperForge.add_page/2`.
- Added support for passing a page callback to `PaperForge.add_page/2`.
- Added callback return-value validation.
- Added metadata creation through `PaperForge.metadata/2`.
- Added output-path validation for `PaperForge.write/2` and
  `PaperForge.write!/2`.

#### Testing

- Expanded document graph tests.
- Added tests for document compression and PDF version configuration.
- Added tests for unsupported document options.
- Added tests for invalid compression values.
- Added tests for compressed PDF output.
- Added tests for uncompressed PDF output.
- Added tests for font reuse and additional font registration.
- Added tests for JPEG and PNG parsing, image registration, image
  deduplication, and image scaling.
- Added tests for top-left and bottom-left coordinate compilation.
- Added tests for margins and text-box layout behavior.
- Added tests that verify every xref offset points to the beginning of its
  object.
- Added a structural round-trip style writer test covering multiple pages,
  fonts, repeated images, metadata, compression, resources, and xref offsets.
- Updated writer tests so they no longer assume compressed stream contents are
  visible as plain text.
- Updated document tests to use explicit PDF reference fields.
- Restored compilation with `--warnings-as-errors`.

### Changed

- Changed the default page content stream behavior to use Flate compression.
- Changed document creation to accept configuration options.
- Changed document creation so only the page tree and catalog are created
  initially.
- Changed font creation to register standard Type 1 fonts only when used.
- Changed the next automatically allocated object identifier to start after the
  initial page tree and catalog objects.
- Changed page compilation to register fonts and images dynamically.
- Changed page image compilation to detect supported image formats before
  registering image XObjects.
- Changed page compilation to flow through `PaperForge.PageCompiler`.
- Changed page resource generation to use `PaperForge.PageResources`.
- Changed text rendering to use registered font resource names instead of a
  hardcoded font resource.
- Changed text positioning to support page margins and configurable origins.
- Changed metadata values to use automatic PDF string encoding.
- Changed JPEG files to be embedded directly as PDF image streams.
- Changed the document structure to use explicit reference field names:
    - `root_reference`
    - `pages_reference`
    - `info_reference`
- Changed tests to validate behavior and structure rather than relying on
  compressed stream contents or fixed internal assumptions.
- Changed page streams to select filters from the document configuration.
- Changed multiline text rendering to use text wrapping and layout metrics.

### Fixed

- Fixed duplicate `@doc` warnings for multi-clause `PaperForge.add_page/2`.
- Fixed the missing `PaperForge.Font.definition_to_dictionary/1` function.
- Fixed JPEG bitstring matching by pinning `payload_length`.
- Fixed compilation under `mix compile --warnings-as-errors`.
- Fixed font resource reuse across pages.
- Fixed repeated image embedding by deduplicating JPEG binaries.
- Fixed repeated image embedding by deduplicating PNG binaries.
- Fixed image aspect-ratio calculations when only one dimension is provided.
- Fixed top-left coordinate conversion for box-shaped operations.
- Fixed page resource dictionaries for multiple fonts and image XObjects.
- Fixed metadata encoding for characters outside simple PDF literal-string
  ranges.
- Fixed stream filter serialization for compressed page content.
- Fixed tests that referenced removed or renamed document fields.
- Fixed tests that expected uncompressed text while compression was enabled.

### Internal

- Added `PaperForge.PageCompiler` as the central page operation compiler.
- Added separate registries for fonts and images.
- Added normalized built-in font definitions.
- Added font metric tables.
- Added dedicated modules for:
    - Compression
    - Coordinates
    - Margins
    - Font registration
    - Image registration
    - JPEG parsing
    - PNG parsing
    - Page compilation
    - Page resources
    - String encoding
    - Text measurement
    - Text wrapping
    - Text boxes
    - Image drawing
- Continued using `iodata` for PDF command and document construction.
- Kept PDF object references separate from indirect object values.

## [0.1.0] - 2026-07-26

### Added

- Initial PaperForge project structure
- Pure Elixir PDF generation without external rendering tools
- PDF primitive serialization for:
    - Null values
    - Booleans
    - Integers
    - Floating-point numbers
    - Names
    - Literal strings
    - Arrays
    - Dictionaries
    - Indirect references
    - Streams
- Indirect PDF object representation
- PDF object references with generation numbers
- PDF stream support with automatic byte-length calculation
- Internal document object graph
- Automatic PDF object ID allocation
- Document catalog generation
- PDF page tree generation
- Multi-page document support
- Cross-reference table generation
- PDF trailer and `startxref` generation
- Binary PDF output
- File-writing API
- Built-in Helvetica font support using WinAnsiEncoding
- A3, A4, A5, Letter, Legal, and custom page sizes
- Portrait and landscape page orientations
- Text drawing with:
    - Position
    - Font size
    - Fill color
- Line drawing with:
    - Start and end coordinates
    - Stroke color
    - Configurable line width
- Rectangle drawing with:
    - Stroke
    - Fill
    - Stroke color
    - Fill color
    - Configurable line width
- Circle drawing using cubic Bézier curves
- RGB color support
- 8-bit RGB color helpers
- Grayscale color support
- Basic PDF metadata:
    - Title
    - Author
    - Subject
    - Keywords
    - Creator
    - Producer
- Example documents for text, multiple pages, and graphics
- Unit tests for the PDF serializer, document graph, pages, and writer

### Technical details

- Uses `iodata` internally to reduce unnecessary binary concatenation
- Produces traditional PDF cross-reference tables
- Uses generation `0` for newly generated indirect objects
- Uses native PDF coordinates with the origin at the bottom-left corner
- Isolates graphic operations using the PDF `q` and `Q` operators

[0.5.0]: https://github.com/Manuel1471/paper_forge/compare/v0.4.0...v0.5.0
[0.6.0]: https://github.com/Manuel1471/paper_forge/compare/v0.5.0...v0.6.0
[0.4.0]: https://github.com/Manuel1471/paper_forge/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Manuel1471/paper_forge/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Manuel1471/paper_forge/releases/tag/v0.2.0
[0.1.0]: https://github.com/Manuel1471/paper_forge/releases/tag/v0.1.0
