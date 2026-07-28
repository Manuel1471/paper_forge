# Contributing to PaperForge

Thank you for your interest in contributing to PaperForge.

PaperForge is a pure Elixir PDF document engine focused on direct PDF generation, Unicode text, embedded fonts, document layout, navigation, performance, and future concurrent and distributed document generation on BEAM.

Contributions of all kinds are welcome, including bug reports, documentation, tests, examples, performance improvements, architecture discussions, and code.

## Project goals

PaperForge aims to provide:

- Pure Elixir PDF generation
- No browser, native executable, or external rendering-service dependency
- Predictable PDF output
- A clean and stable public API
- Strong support for Unicode, fonts, images, tables, and document layout
- Good performance and memory behavior
- Compatibility with common PDF readers
- A foundation for future HTML and CSS document rendering

When contributing, prefer changes that support these goals without introducing unnecessary runtime dependencies or duplicated layout logic.

## Before contributing

Before opening an issue or pull request:

1. Search existing issues and pull requests.
2. Confirm the behavior against the latest `main` branch.
3. Keep the proposed change focused.
4. Add or update tests when changing behavior.
5. Update documentation when changing a public API.
6. Avoid combining unrelated refactors and features in one pull request.

For large architectural changes, open an issue or discussion first.

Examples include:

- Public API redesigns
- Layout-engine changes
- New font formats
- New PDF object types
- Major table or pagination behavior
- HTML or CSS support
- Changes that add runtime dependencies
- Backward-incompatible changes

## Development setup

Clone the repository:

```bash
git clone git@github.com:Manuel1471/paper_forge.git
cd paper_forge
```

Install Hex and Rebar if needed:

```bash
mix local.hex --force
mix local.rebar --force
```

Install dependencies:

```bash
mix deps.get
```

Compile the project:

```bash
mix compile
```

Run the test suite:

```bash
mix test
```

Generate the documentation:

```bash
mix docs
```

Open the generated documentation on macOS:

```bash
open doc/index.html
```

## Required checks

Before opening a pull request, run:

```bash
mix format --check-formatted
mix clean
mix compile --warnings-as-errors
mix test
mix docs
mix hex.build
```

All commands should complete successfully.

Generated PDFs related to the change should also be opened manually in at least one PDF reader.

For changes affecting PDF structure, fonts, navigation, images, streams, or cross-reference offsets, validate the generated files with additional readers or tools when available.

Examples:

```bash
qpdf --check tmp/example.pdf
mutool info tmp/example.pdf
pdftotext tmp/example.pdf -
```

These tools are optional development utilities and are not runtime dependencies of PaperForge.

## Code style

PaperForge follows standard Elixir formatting and style conventions.

Format changed files with:

```bash
mix format
```

General guidelines:

- Prefer small, focused modules.
- Use descriptive names.
- Add typespecs to public functions.
- Add module and function documentation to public APIs.
- Keep internal implementation details out of the public API.
- Prefer pattern matching and explicit validation.
- Return structured errors where appropriate.
- Avoid hidden mutable global state.
- Prefer immutable data and process-safe designs.
- Use iodata when building large serialized outputs.
- Avoid unnecessary binary copies.
- Do not add dependencies without a strong reason.

## Public API guidelines

Public APIs should be:

- Consistent with existing naming
- Documented with examples
- Covered by tests
- Explicit about accepted options
- Predictable in error behavior
- Compatible with safe and bang variants when applicable

Use keyword lists for public options unless an existing API establishes a different pattern.

Prefer consistent names such as:

- `width`
- `height`
- `x`
- `y`
- `align`
- `valign`
- `margins`
- `font`
- `size`
- `page_break_before`
- `page_break_after`
- `keep_together`

Avoid exposing low-level PDF structs unless they are intentionally part of the stable public API.

## Testing guidelines

Every bug fix should include a regression test.

Every new feature should include tests at the appropriate levels.

### Unit tests

Use unit tests for isolated behavior such as:

- Serialization
- String encoding
- Color conversion
- Font parsing
- Glyph mapping
- TrueType checksums
- Image parsing
- Text measurement
- Block measurement
- Pagination decisions

### Integration tests

Use integration tests for behavior involving multiple modules, such as:

- Font registration and rendering
- Unicode extraction through `/ToUnicode`
- PNG transparency through `/SMask`
- Multipage flow
- Paginated tables
- Repeated headers
- Internal links
- Named destinations
- Outlines and bookmarks
- Resource deduplication

### Structural PDF tests

Structural tests should verify details such as:

- Catalog and page-tree references
- Cross-reference offsets
- `startxref`
- Stream lengths
- Object references
- `/Type0`
- `/CIDFontType2`
- `/FontFile2`
- `/ToUnicode`
- `/Names`
- `/Outlines`
- `/Annots`
- `/Dest`
- `/SMask`

### Visual tests

When a change affects rendering, create a small example PDF and inspect it manually.

Visual checks are especially important for:

- Text alignment
- Text wrapping
- Unicode output
- Table pagination
- Headers and footers
- Images
- Transparency
- Internal navigation
- Bookmarks
- Page breaks

## Test fixtures

Keep fixtures small and legally redistributable.

For font fixtures:

- Confirm that the license allows redistribution.
- Prefer open-source fonts with clear licenses.
- Do not commit proprietary system fonts.
- Avoid including large font families when one small fixture is sufficient.

For image fixtures:

- Prefer generated or openly licensed images.
- Keep file sizes reasonable.
- Do not include private or copyrighted assets without permission.

Fixtures used only for tests or benchmarks should not be included in the Hex package unless intentionally required.

## Benchmarks

Performance changes should include before-and-after measurements when possible.

Useful benchmark areas include:

- PNG parsing
- TrueType parsing
- Text measurement
- Font subsetting
- Large tables
- Multipage flow
- Serialization
- Compression
- Memory usage
- Concurrent document generation

Benchmarks should not use strict timing assertions in normal tests.

If a performance test is included in the test suite, use a generous limit that is unlikely to fail on slower CI environments.

Document:

- Input size
- Hardware or environment
- Number of iterations
- Median or average result
- Memory behavior
- Any relevant trade-offs

## PDF compatibility

Changes should preserve compatibility with common readers.

When possible, test generated PDFs with:

- Adobe Acrobat Reader
- macOS Preview
- Chrome PDF Viewer
- Firefox PDF.js
- iOS PDF viewers
- Android PDF viewers

A generated PDF opening successfully is not always enough. Also verify relevant behavior such as:

- Text selection
- Text search
- Unicode copying
- Internal links
- Bookmarks
- Transparency
- Image rendering
- Page counts
- Table pagination

## Error handling

Prefer clear, structured errors.

Errors should include useful context when possible, such as:

- Page number
- Block identifier
- Font key
- Glyph codepoint
- Table row
- Table column
- Required height
- Available height
- Destination name
- Object identifier

Avoid generic errors when a more specific error can help the caller understand and fix the problem.

## Documentation

Update documentation whenever you:

- Add a public function
- Change a public option
- Change error behavior
- Add a limitation
- Add a supported format
- Add a new document feature
- Deprecate an API

Documentation changes may include:

- `README.md`
- Module documentation
- Function documentation
- `CHANGELOG.md`
- Guides
- Examples
- Migration notes

Examples should be complete, runnable, and aligned with the current public API.

## Changelog

PaperForge follows Keep a Changelog and Semantic Versioning.

Add user-visible changes under the appropriate section:

```markdown
## [Unreleased]

### Added

### Changed

### Deprecated

### Fixed

### Security
```

Do not add implementation details that do not affect users unless they explain an important architectural or performance improvement.

Be precise when describing partial support.

For example, distinguish between:

- Planning physical TrueType subsetting
- Subsetting generated width arrays
- Reconstructing a physically subsetted `/FontFile2`

Do not describe planned behavior as already supported.

## Commit messages

Use clear and focused commit messages.

Examples:

```text
Add paginated table header repetition
```

```text
Fix composite glyph dependency expansion
```

```text
Add internal PDF destinations and links
```

```text
Improve PNG parsing memory usage
```

For release commits:

```text
Release PaperForge v0.5.0
```

Avoid vague messages such as:

```text
Update code
```

```text
Fix stuff
```

## Pull requests

Pull requests should include:

- A clear title
- A summary of the change
- Motivation
- Implementation notes when relevant
- Tests added or updated
- Documentation changes
- Known limitations
- Compatibility considerations
- Performance impact when relevant

A suggested template:

```markdown
## Summary

Describe the change.

## Motivation

Explain the problem being solved.

## Changes

- Change one
- Change two
- Change three

## Validation

- [ ] `mix format --check-formatted`
- [ ] `mix compile --warnings-as-errors`
- [ ] `mix test`
- [ ] `mix docs`
- [ ] `mix hex.build`
- [ ] Generated PDFs inspected manually

## Compatibility

Describe readers, platforms, or existing APIs affected.

## Limitations

Describe anything intentionally not supported.
```

Keep pull requests focused enough to review safely.

Large changes may be divided into:

1. Internal foundation
2. Public API
3. Integration
4. Tests
5. Documentation

## Bug reports

A useful bug report should include:

- PaperForge version
- Elixir version
- Erlang/OTP version
- Operating system
- Minimal reproduction
- Expected behavior
- Actual behavior
- Error or stack trace
- Generated PDF when safe to share
- Reader used to open the PDF

Example environment command:

```bash
elixir --version
mix hex.info paper_forge
```

Do not include private documents, credentials, or confidential customer data.

## Feature requests

Feature requests should explain:

- The document use case
- The current limitation
- A minimal example of the desired API
- Whether the change affects layout, fonts, images, navigation, or writing
- Expected PDF behavior
- Compatibility requirements
- Performance concerns

Features that duplicate existing layout logic may be redesigned around the shared layout engine instead of being added as isolated behavior.

## Security issues

Do not report security vulnerabilities in a public issue when disclosure could put users at risk.

Instead, contact the maintainer privately through the repository's available security reporting channel.

Security-sensitive areas include:

- Resource-path handling
- Remote resource loading
- Font parsing
- Image decompression
- Untrusted HTML or CSS in future versions
- Excessive memory or CPU usage
- Malformed binary inputs
- Arbitrary file access
- Denial-of-service behavior

## Backward compatibility

Before `1.0.0`, the public API may still evolve.

Even so, contributors should avoid unnecessary breaking changes.

When a breaking change is justified:

- Document the reason.
- Add migration instructions.
- Prefer deprecation before removal.
- Update examples and guides.
- Add changelog entries.
- Keep the change focused.

After `1.0.0`, changes to stable public APIs should follow Semantic Versioning.

## Dependencies

PaperForge aims to remain lightweight.

Before adding a dependency, consider:

- Can this be implemented safely in PaperForge?
- Is the dependency actively maintained?
- Is it required at runtime?
- Does it add native binaries?
- Does it complicate releases?
- Does it affect concurrency or portability?
- Is its license compatible?
- Can it remain optional or development-only?

Runtime dependencies should provide clear value.

## Scope

PaperForge focuses on generating new PDF documents.

The following areas may be outside the current scope or planned for later versions:

- Editing existing PDFs
- Digital signatures
- AcroForms
- PDF/A and PDF/UA conformance
- OpenType CFF
- TrueType Collections
- Complex text shaping
- Full HTML and CSS rendering

Check the current roadmap and open an issue before beginning work in these areas.

## License

By contributing to PaperForge, you agree that your contributions will be licensed under the same license as the project.

PaperForge is available under the MIT License.
