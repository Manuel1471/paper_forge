# Changelog

All notable changes to PaperForge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.2.0]: https://github.com/Manuel1471/paper_forge/compare/v0.2.0
[0.1.0]: https://github.com/Manuel1471/paper_forge/releases/tag/v0.1.0
