# PaperForge 1.5.0 — PDF Interoperability & Transformation Engine

PaperForge now works with existing PDFs as well as generating new documents.
This release establishes an object-graph foundation for inspection, analysis
and transformation, while refining layout, scientific typography, forms,
charts and configurable declarative components.

## Open, inspect and transform existing PDFs

- Read cross-reference streams, compressed object streams, hybrid references,
  incremental trailer chains, active object generations and inherited resources.
- Decode supported filter chains and open supported AES-256 R5/R6 documents
  with a password.
- Inspect metadata, forms, annotations, attachments, outlines and signatures.
- Analyze object counts, revisions, fonts, images, duplicate resources,
  broken/orphaned references, encryption, tagged-PDF markers and normalization opportunities.
- Delete, rotate, reorder, extract and merge pages; update metadata, add
  watermarks and normalize document graphs.
- Inspect files from the terminal with `mix paper_forge.inspect document.pdf`,
  including JSON output and password input through an environment variable.

```elixir
{:ok, pdf} = PaperForge.open("contract.pdf")
{:ok, analysis} = PaperForge.analyze(pdf)

pdf
|> PaperForge.rotate_pages([1], 90)
|> PaperForge.add_watermark("CONFIDENTIAL")
|> PaperForge.update_metadata(title: "Reviewed contract")
|> PaperForge.write!("reviewed.pdf")
```

## More control over PDF presentation

- Configurable containers, rows, columns, arbitrary block grids and overlays.
- Vector shapes and SVG icons, compact badges, linked buttons with optional
  icons, and rounded/circular images with captions and focal-point cropping.
- Measured cell alignment, explicit sizing and spacing, inherited styles and
  design tokens; nested navigation remains available inside compositions.
- Rich text with resolved embedded-font metrics, inline styles, underline,
  strikethrough and links.
- Configurable QR payload, size, alignment, correction level, quiet zone and
  colors, rendered as compact vector paths.
- Refined AcroForm sizing, padding, borders, text fitting and field appearances.
- Improved Math and Scientific proportions, nested expression geometry,
  matrix row heights, integral bounds and alignment.
- More readable chart scales, signed/zero-value handling, legends and dense labels.
- Corrected Unicode handling in bookmarks, metadata, forms, annotations,
  attachment names and XMP.

## Reliability and concurrent rendering

- Preserve nested cache writes and distinguish template map/list identities.
- Honor runtime theme overrides and reject missing or cyclic design tokens.
- Measure index leaders with font metrics and retain explicit endnotes.
- Fit protection watermarks and preserve third-party PieceInfo.
- Stabilize integrity fingerprints across serialization and compression.
- Store child block trees once and consolidate concurrent resource sampling.
- Enforce final resource budgets for fast jobs and expose optional
  `worker_heap_size` tuning with conservative defaults.

Short local measurements of small PDFs at 10 workers improved from 32,985 to
37,841 PDF/s with defaults, and to 41,288 PDF/s with a larger initial heap.
These are in-memory microbenchmarks, not production service capacity.
Results vary by workload; the default QR case at four workers regressed.
Raw measurements, sampled-memory tradeoffs and methodology are retained in
`benchmarks/results/concurrent-tuning/`.

## Examples and verification

- Atlas: a 27-page declarative report with chart galleries and readback checks.
- Lumen: an eight-page visual notebook with configurable forms and scientific content.
- A focused mathematical typography specimen, editorial navigation example,
  data-driven QR invitation and four-page primitive gallery.
- Local verification: 442 regular checks and two separate fuzz checks passed.
  Formatting, strict compilation and documentation generation passed.
- The primitive gallery was visually reviewed; independent checks validated
  Unicode text, link bounds, clipping state and QR decoding.

## Upgrade notes and limits

Requires Elixir `~> 1.20`. Install with:

```elixir
{:paper_forge, "~> 1.5.0"}
```

Review `MIGRATING.md` before upgrading. Typography defaults can change pagination.
Persisted template hashes and protection fingerprints use corrected calculations;
regenerate older values from trusted originals.

Visual compositions paginate atomically and reject content that exceeds the
available page. Use ordinary flow blocks for content that must split across pages.

This release is not a general malformed-PDF repair engine. RC4/AES-128 import,
XFA, LZW/TIFF predictors and document-level catalog merging remain unsupported.
Signature inspection is structural and does not perform cryptographic verification.
Editing a signed PDF does not preserve its signature validity. Math is native
measured typesetting, not a full TeX engine. Refer to `INTEROPERABILITY.md`
for the precise supported scope.
