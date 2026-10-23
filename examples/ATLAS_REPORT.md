# Atlas 2026: PaperForge 1.5.0 editorial workload

A fictional logistics annual report in Spanish, designed to exercise actual
layout and PDF interoperability rather than assemble isolated drawing demos.
It currently generates 27 A4 pages, 17 chapters and a 120-row route register
flowing automatically across nine pages. All figures are synthetic and
reproducible; no company results or environmental certification are implied.

The complete design lives in [`atlas_2026.paperforge`](atlas_2026.paperforge):
sections, full-bleed cover, inline SVG artwork, charts, text and tables are JSON
data. No custom rendering callbacks are registered. The small Elixir runner
supplies the 120 deterministic route rows, attaches the dataset and verifies
generation and transformation. Edit the `.paperforge` file to change the design.

Four gallery pages exercise signed bars and areas, fractional line values,
categorical scatter, pie/donut composition, 40 categories, empty series and
all-zero values. Axes include zero; labels are sampled without dropping marks.

## Generate

From the repository root:

```sh
mix run examples/paper_forge_1_5_report.exs
```

No external fonts, images, network access or Python packages are required for
generation. Illustrations and charts are PDF vectors. Built-in Helvetica fonts
use WinAnsi for Spanish accents and punctuation.

Outputs, under `output/pdf/atlas-2026/` (ignored by Git):

- `atlas-2026-report.pdf`: the complete report, with clickable contents,
  chapter bookmarks, repeated table headers, footnotes and an embedded dataset.
- `atlas-2026-extract.pdf`: four imported pages, a watermark, updated metadata
  and a 90-degree rotation on the fourth page. This is a transformation sample,
  not a replacement for the main report.
- `routes.json`: the same 120 rows attached to the PDF.
- `verification.json`: 14 generation/readback checks and four transformation
  checks. Generation fails if any check fails.

The annual revenue series sums to MXN 1,090 million. The route register sums to
34,140 scheduled trips. Chapter 11 explains definitions and limitations.

## Independent readback

The optional checker uses pypdf, not PaperForge's parser:

```sh
python3 -m venv /tmp/atlas-reader
/tmp/atlas-reader/bin/pip install pypdf
/tmp/atlas-reader/bin/python examples/verify_atlas.py
```

It writes `independent-verification.json` and fails if any of its 12 checks
fails: physical page count, all route IDs in order without duplication, Spanish
text extraction, absence of mojibake, exact attachment contents, chapter
destinations, page footers, repeated headers, extracted page count, rotation,
watermark text on all extracted pages and updated metadata.

For visual review with Poppler installed:

```sh
mkdir -p tmp/atlas-render
pdftoppm -scale-to 1100 -png output/pdf/atlas-2026/atlas-2026-report.pdf tmp/atlas-render/page
```

Review all pages, especially the index, mixed-size text, page 12's transition
into the route table, subsequent table headers, the final table rows, footnotes
and the visible layout cases near the end. Rendering is a separate check from
text extraction. PDF screenshots are not committed; the source regenerates them.

## Regression coverage and limits

```sh
mix test test/paper_forge/atlas_report_test.exs test/paper_forge/builtin_encoding_test.exs
```

The integration test builds the report, writes and reopens it, validates the
layout/graph and executes the transformation. Bounds checks cover automatic
block positions. The cover deliberately paints to the page edge; table bounds
measure drawn rows rather than trailing whitespace. Custom illustrations are
reviewed visually, not certified by the block-bounds check.

This workload does not establish universal reader compatibility, PDF/A,
PDF/UA, cryptographic signature verification, encrypted import or malformed-PDF
repair. Those need their own fixtures and tests. It does demonstrate the
features it uses with reproducible checks and an independently readable output.

The first visual render exposed raw UTF-8 bytes being emitted under a WinAnsi
font dictionary. The accompanying encoding fix and byte-level regression cover
accents, the bullet, euro sign and em dash; unrepresentable text now requires an
embedded font rather than silently generating corrupt visible text.
