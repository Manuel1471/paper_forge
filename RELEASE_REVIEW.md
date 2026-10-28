# PaperForge 1.5: review of the 1.4 authoring surface

Local review: 2026-10-25, branch `release/v1.5.0`, Elixir 1.20.2 / OTP 29.
This records the exercised cases and remaining boundaries, not a guarantee that
all PDFs or all combinations of authoring options are supported.

## Coverage and corrections

| Area | Evidence and changes |
| --- | --- |
| Unicode outside pages | Exact round trips for metadata, XMP, outlines, document/file-annotation attachments, annotation contents/author/subject, field names/tooltips/defaults/values and choice labels. Cases include ñ, €, curly quotes, NBSP, Japanese and emoji. |
| Embedded font text | Distinct CIDs preserve Ω and Ω even when the font maps both to one glyph. Cyrillic and Greek field appearances are checked with an embedded font. |
| Forms | Editing regenerates appearances, choices display their label, nil clears values, radio/checkbox states remain consistent. Flattening paints existing appearances and removes all widgets while retaining other annotations. |
| Form presentation | Inset borders, proportional checks, circular radio controls, centered button labels, configurable font/size/color/padding/alignment, measured single-line fitting without truncating stored values. |
| HTML / CSS / Markdown / SVG | UTF-8 and inline SVG preserved; bounded XML parser avoids input-created atoms and rejects entity declarations. Existing strict CSS and markup tests retained. SVG anchors now use the actual rendered font metrics. |
| Scientific authoring | Nested matrix cells reserve enough height, integrals include their body/variable bounds, custom equation destinations resolve without duplicate registration. Math can be centered/right-aligned in its actual layout column. |
| Declarative design systems | Styles and templates consistently use string identifiers, including names that already exist as VM atoms. Tests retain bounded identifier behavior. |
| Charts and tables | Existing six-type chart tests and Atlas gallery retained. Radial legends are vertically centered. Lumen exercises table striping, padding, wrapped cells, explicit column widths and shared chart colors. |
| Interoperability / security | Existing parser, page-composition, encryption, protection, signing and graph tests rerun. Protected and signed scientific examples regenerated. Signature verification and arbitrary catalog merging are not claimed. |
| 1.4 production features | Existing resource limits, error contracts, cancellation, timeout, atom-safety, cache, concurrent determinism and soak tests retained and rerun. |

No useful tests were removed in this review. Compiled-style assertions were
updated for consistent string keys. New regression tests cover the defects above;
independent readers complement internal round trips.

## Reproduce

```sh
mix test
mix test.fuzz
mix credo diff --from-git-ref 8200658 --strict
mix docs --warnings-as-errors
mix run test/support/unicode_review.exs
python3 test/support/verify_unicode.py
mix run examples/lumen_visual_2026.exs
python3 examples/verify_lumen.py
mix run examples/paper_forge_1_5_report.exs
python3 examples/verify_atlas.py
```

Python checks require `pypdf`; rendering checks use Poppler. These are development
verification tools, not runtime dependencies of PaperForge.

Results: **402 tests/properties passed**, plus **2 opt-in fuzz tests/properties**.
Differential Credo adds no issues relative to the outline fix; docs compile with
warnings treated as errors. The independent Unicode fixture passes **19 checks**.
Lumen has **8 pages, 7 canonical fields and 8 widget appearances**. Atlas retains
**27 pages** and passes its **13 independent readback checks**, plus its Elixir
layout/transformation checks.

All eight Lumen pages were rendered and visually reviewed. The Unicode fixture's
interactive and flattened editions produce pixel-identical Poppler images at
1000-pixel page height. This checks visible preservation as well as logical field
data; it does not promise identical behavior in every PDF viewer.

Legacy examples also generate: the five-page Elixir 1.4 showcase, the four-page
`.paperforge` showcase, the three-page HTML/CSS showcase, and the protected/signed
scientific report. The visual notebook supplements these examples; Atlas remains
the larger pagination and chart demonstration.

## Performance snapshot

```sh
SAMPLES=5 WARMUPS=1 mix run benchmarks/render_profiles.exs
```

On this local development runtime, the 5,000-row workload produced **179 pages**
and **616,481 bytes**. Median total time was **776.55 ms** across five samples
(after one warmup); maximum observed process memory was **81,034,704 bytes**.
The small and medium profiles also completed. These are measurements of this
workload and machine, not a universal latency target or a controlled before/after
speedup comparison. Matrix traversal and field-tree traversal avoid repeated
whole-list work; no speculative optimization replaced the verified behavior.

## Boundaries to retain for release

- Unicode object strings do not require a font, but visible page/field text still
  needs glyph coverage. Complex-script shaping and arbitrary fallback fonts are
  not implied by Unicode metadata support.
- Original typography of arbitrary imported forms is not fully reconstructed on
  edit. Current-document style options are retained in memory; flattening existing
  valid appearances preserves them. XFA remains unsupported.
- The HTML/CSS and SVG importers implement documented subsets, not browser layout.
- PDF writing remains a complete rewrite. Existing signatures are not preserved
  through transformation; append-only editing and signature verification remain
  outside the release scope described in `INTEROPERABILITY.md`.
- Real-world producer files and additional reader implementations remain valuable
  compatibility inputs beyond the fixtures and examples exercised here.

## Presentation follow-up: 2026-10-26

The Lumen notebook now defaults to a compact profile: 22-point text/choice
fields, 12-point selections, 25-point minimum table rows, 155-point chart panels,
16-point formula text and separately controlled 11-point equation headings.
A comfortable theme changes shared tokens/styles, including 28-point fields.
All presentation settings remain in the `.paperforge` source. The runner only
selects a theme, generates the output and checks its fields.

Added six regression tests for inherited field styles, geometry tokens and theme
overrides, invalid geometry/style cycles, independent formula heading sizes,
chart legend/radial sizes, borderless fields/tables and footnote rendering.
The full suite now passes **408 tests/properties**, plus **2 fuzz cases**.
Both profiles pass independent field/value/appearance checks and retain eight
pages. The published JSON Schema accepts the source and both geometry formats.
All compact pages and detailed form/formula/table views were rendered and
reviewed. Atlas still passes its 27-page generation and 13 independent checks.
Differential Credo adds no issues and documentation builds without warnings.

See the compact-presentation section of `DECLARATIVE.md` for the options,
precedence rules, dimension units, reusable styles and theme commands. Existing
API defaults remain available; presentation changes are configured explicitly.

## Math / Scientific visual follow-up: 2026-10-26

The mathematical renderer now uses 11-point Times Roman by default, proportional
ornaments and thinner rules. Rows align on a mathematical axis; superscripts fit
inside their measured boxes. Mixed-height matrices reserve each row's own height
and accumulate row offsets in a single traversal. Scientific label/heading
defaults are reduced without removing explicit presentation overrides.

The two-page `math_scientific_visual.paperforge` specimen covers fractions,
scripts, radicals, integrals, matrices and nested expressions, plus a 9/11/14-point
comparison. Both pages and Lumen's updated scientific page were rendered and
visually checked. Independent pypdf readback confirms two pages, Times Roman
resources and the page-one equation reference. The legacy Elixir 1.4 showcase
still generates. Full validation: **410 tests/properties plus 2 fuzz cases**,
differential Credo with no new issues, and documentation compiled without warnings.

## 1.2 / 1.3 follow-up — 2026-10-26

Reviewed the release inventories against the existing declarative, security,
signature, protection and compliance regression suites. Retained these tests:
imports, limits, typed variables, themes/components, credentials, AES opening
with Poppler, signature provider contracts and structural conformance checks
cover distinct behavior and should not be deleted as redundant.

Fixed two concrete areas:

- Compiled cache hashing previously canonicalized maps into lists, creating
  identical hashes for empty maps/lists and maps/lists of pairs. Deterministic
  Erlang encoding now preserves term types and avoids an extra recursive copy.
- Protection watermarks now use measured text width and rotated positioning,
  shrink to the available crop box, support margins and offsets, preserve
  inherited/indirect resources, use unique resource names on repeated calls,
  and isolate the existing page graphics state. Added numeric validation.

The one-page native declarative example was rendered with Poppler and visually
inspected. This is targeted coverage, not a claim of exhaustive cryptographic
review or external PDF/A / PDF/UA certification. No new signature algorithm,
provider, network timestamp service or archival certification was introduced.
The performance benefit of removing cache normalization is not quantified.

### Completed configuration and integrity follow-up

- Explicit runtime themes now override the source default. Token aliases resolve
  recursively with missing-reference, cycle and depth errors. Watermark visual
  options consume the same theme tokens; literal watermark text is preserved.
- Protection no longer discards third-party PieceInfo. Its checksum excludes only
  its own stored checksum, includes object generations/document references, and
  hashes canonical PDF objects incrementally. Regression fixtures reproduce the
  former false `modified` result after writing/reopening a compressed document,
  including Unicode hex-string metadata, and verify the correction.
- `design_protection_review.paperforge` and its runner produce two one-page PDFs,
  compact and comfortable. Both were rendered through Poppler, visually inspected,
  reopened and verified for page count and fingerprint. The schema accepts the
  visual token references and validates the example.
- Validation: 419 normal tests/properties and 2 fuzz tests pass. Existing AES,
  signing/provider, declarative imports/components and structural compliance tests
  remain in the suite; no redundant tests were removed without evidence.
- This follow-up changes Core after the frozen benchmark. The historical campaign
  is preserved unchanged and does not measure these later modifications. No new
  throughput claim is made. Removing cache normalization avoids an intermediate
  recursive copy; fingerprint hashing avoids materializing the whole object graph
  as one Erlang binary. End-to-end performance effects are not quantified here.

## 1.0 / 1.1 follow-up

Reviewed the release inventory covering baseline layout/navigation/notes and
production concurrency/cache features. Existing table, image, font, writer,
telemetry, concurrency, timeout/cancellation and determinism coverage was retained.
This is targeted regression work, not a claim that all historical features are
bug-free or an independent conformance/security certification.

Concrete corrections:

- Fast concurrent jobs now report final memory and have completed reductions and
  memory budgets checked; formerly jobs finishing before the poll bypassed those
  budgets and often reported zero memory. Minor-GC deltas cannot become negative
  after a counter reset (they still are not cumulative VM totals).
- Cache producers that invoke another cache lookup no longer overwrite newly
  populated namespaces. Nested same-key inserts do not duplicate FIFO queue entries
  or allow stale eviction slots to violate the configured entry bound. Cached work
  is retained instead of recomputed; no throughput improvement is claimed.
- Explicit endnotes are no longer silently dropped. Entry styles and independent
  heading options are honored, with compact proportional defaults.
- TOC leaders use glyph metrics at placement time and honor real content width,
  indentation and entry spacing; title styling is independently configurable.

Evidence: 424 normal tests/properties pass; fuzz suite passes separately. Added
regressions cover fast-job limits, cache reentrancy/eviction, explicit endnotes and
measured TOC alignment. The three-page `editorial_1_0_1_1.paperforge` sample was
rendered through Poppler and visually checked, including its corrected first-page
alignment. The frozen historical benchmark was not edited or rerun for this work.

## Visual primitives and concurrent tuning (2026-10-28)

- Removed the six experimental business compositions; replaced them with
  reusable declarative visual primitives documented in VISUAL_BLOCKS.md.
- Final verification: 442 regular tests passed (including 3 properties);
  2 separately selected fuzz checks passed. Documentation builds with
  warnings-as-errors. Gallery validates against the JSON Schema.
- Inspected all four rasterized gallery pages. Independent pypdf checks
  confirm four pages, two in-bounds links, six clipping operations, balanced
  graphics state and accented text. macOS Vision decodes the gallery QR.
- Existing Credo refactoring findings remain; strict Credo is not globally clean.
- Concurrent measurements and memory tradeoffs are retained in
  benchmarks/results/concurrent-tuning/comparison.md. The default is conservative;
  increased initial heaps are opt-in. Small-PDF throughput improved, but
  default QR throughput at four workers regressed in this short experiment.
  These measurements do not establish production service capacity.
- Atomic visual compositions intentionally do not split across pages.
