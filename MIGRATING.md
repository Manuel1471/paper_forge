# Migrating PaperForge

## Migrating from 1.2 to 1.3

PaperForge 1.3 is backward compatible with the documented 1.2 public API.
Existing Elixir and `.paperforge` documents continue to render without adding
security, signature, protection, or compliance policies.

Applications may adopt the new output features independently:

1. Pass AES passwords only in final `to_binary/2`, `write/3`, or `write!/3`
   options; do not store credentials in a document or template.
2. Use the default PKCS#8 signature provider for an Elixir/OTP-only runtime, or
   configure `PaperForge.Signature.Provider` for an HSM or signing service.
3. Add declarative `security`, `signature`, `protection`, and `compliance`
   policies while keeping credentials in `PaperForge.Declarative.write/4`.
4. Supply and validate an ICC profile before enabling PDF/A preparation.
5. Follow `PHOENIX.md` when rendering inside HTTP requests or bounded
   background jobs.

The default runtime still requires no native compilation or external
executable. OpenSSL is invoked only when an application explicitly selects the
optional PKCS#12/PFX certificate source.

## Migrating from 1.1 to 1.2

PaperForge 1.2 is backward compatible with the documented 1.1 public API. No
existing Elixir-authored document must be converted to `.paperforge`.

Applications can adopt declarative templates incrementally:

1. Move one document's static structure into a version `"1"` JSON template.
2. Declare the runtime input under `variables` and call
   `PaperForge.Declarative.validate/2` at the application boundary.
3. Move repeated style values into design tokens and named styles.
4. Extract repeated block groups into declarative components.
5. Supply an application-owned `PaperForge.DesignSystem` when several
   templates share the same visual language.
6. Register existing `Flow.custom/2` designs through
   `PaperForge.Declarative.Registry` when a template must orchestrate trusted
   Elixir components.

Legacy declarative version `"0"` maps using `schema` and `content` can be
upgraded with `PaperForge.Declarative.migrate/1`. Version `"1"` rejects unknown
template properties, so remove misspelled or application-private keys before
validation. Run `mix paper_forge.validate TEMPLATE DATA.json` in CI during the
migration.

`jason ~> 1.4` is now a runtime dependency and remains pure Elixir. PaperForge
does not evaluate template content as Elixir code. Templates can reference
files and links, so template files should still be controlled by the
application even when their input data comes from users.

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
