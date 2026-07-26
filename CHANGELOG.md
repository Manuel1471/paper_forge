# Changelog

All notable changes to PaperForge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- Text measurement and alignment
- Additional built-in PDF fonts
- Stream compression using FlateDecode
- JPEG image support
- Top-left coordinate helpers
- Basic paragraph layout
- Automatic line wrapping

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

[Unreleased]: https://github.com/Manuel1471/paper_forge/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Manuel1471/paper_forge/releases/tag/v0.1.0