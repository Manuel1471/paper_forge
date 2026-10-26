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
