# Migrating PaperForge

## Migrating from 0.6 to 1.0

PaperForge 1.0 establishes the public compatibility contract described in
`API.md`. Applications upgrading from `0.6.x` should follow these rules:

- Prefer `PaperForge.Flow` and `PaperForge.layout/3` for new documents.
- Treat `PaperForge.Page` as the stable low-level drawing API.
- Run `PaperForge.validate!/1` before storing or sending generated documents.
- Use explicit metadata dates when byte-for-byte reproducibility matters.
- Use `row_split: :split` only when a row may legitimately continue.
- SVG content now renders through an XML-based vector pipeline. Test documents
  that previously relied on unsupported elements being silently ignored.
- Do not depend on internal object identifiers or resource names.

## Images

`width` and `height` continue to stretch images by default for compatibility.
Use `fit: :contain` or `fit: :cover` for aspect-aware layout. `:cover` clips to
the requested box and accepts `focal_point: {horizontal, vertical}` with values
between `0.0` and `1.0`. JPEG EXIF orientation is applied automatically.

## Page templates

Templates may now define `first_header`, `last_header`, `odd_header`,
`even_header`, and matching footer options. Template strings accept
`{section_page}` and `{section_total}` in addition to `{page}` and `{total}`.

## Tables

Scalar table cells remain supported. New documents can use `Flow.cell/2` for
`colspan`, `rowspan`, vertical alignment, per-cell colors, and per-side borders.
Nested flow blocks are converted into measured cell content.

## Text overflow

Height-limited text boxes default to the historical clipping behavior.
Applications can select `overflow: :clip | :ellipsis | :continue | :error`.
The `:continue` result exposes `remaining_lines`.

## International typography

Complex-script shaping is intentionally not advertised yet. The selected
`harfbuzz_ex` integration is waiting for its public API to expose numeric glyph
IDs; glyph names are insufficient for reliable PDF CID mapping. No native
dependency is included until that contract is available.

## Footnotes

Footnotes now append their call marker to the preceding paragraph, heading,
rich-text block, or final table cell:

```elixir
flow
|> Flow.paragraph("Unaudited results")
|> Flow.footnote("Management estimate")
```

Pass `marker: false` when the source already contains its own marker.

## Validation

Serialization now rejects structurally invalid documents:

```elixir
case PaperForge.validate(document) do
  {:ok, report} -> report
  {:error, issues} -> issues
end
```

`PaperForge.to_binary/1` and `PaperForge.write!/2` raise
`PaperForge.ValidationError` for missing required objects, dangling references,
object identity mismatches, invalid page trees, and page-count mismatches.

## Deterministic Output

The same immutable document produces the same PDF bytes. Dynamic metadata such
as `DateTime.utc_now/0` is caller-controlled and must be fixed explicitly when
reproducible artifacts are required.
