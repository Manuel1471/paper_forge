# PaperForge Public API

## Compatibility policy

PaperForge follows Semantic Versioning. Beginning with `1.0.0`, documented
functions, structs, options, and return values in the modules below are covered
by the `1.x` compatibility contract:

- `PaperForge`
- `PaperForge.Flow`
- `PaperForge.Page`
- `PaperForge.PageContext`
- `PaperForge.Color`
- `PaperForge.Document`
- `PaperForge.Image`
- `PaperForge.Metadata`
- `PaperForge.Concurrent`
- `PaperForge.Concurrent.Result`
- `PaperForge.Telemetry`
- `PaperForge.ValidationResult`
- `PaperForge.Declarative`
- `PaperForge.Declarative.Compiled`
- `PaperForge.Declarative.Error`
- `PaperForge.Declarative.Registry`
- `PaperForge.DesignSystem`
- `PaperForge.Security`
- `PaperForge.Protection`
- `PaperForge.Compliance`
- `PaperForge.Signature`
- `PaperForge.Signature.Provider`
- `PaperForge.Signature.Providers.SignCore`
- `PaperForge.Import`
- `PaperForge.Import.CSS`
- `PaperForge.Import.HTML`
- `PaperForge.Import.Markdown`
- `PaperForge.Interoperability`
- `PaperForge.Math`
- `PaperForge.Scientific`
- `PaperForge.AcroForm`
- Public exception modules

Modules whose `@moduledoc` is `false` are implementation details. Their names,
data structures, and functions may change in a minor release.

## Deprecations

A public API is deprecated before removal. Deprecations include an
`@deprecated` message naming the replacement and remain available throughout
the current major release. Removal happens only in the next major version.

## Output compatibility

Patch releases preserve document semantics but do not promise identical bytes
across different PaperForge versions. Identical inputs within the same version
produce deterministic bytes when callers provide deterministic metadata.

## Diagnostics contract

`PaperForge.validate/1` returns `{:ok, %PaperForge.ValidationResult{}}` for a
structurally valid document. Its `warnings` field is non-blocking and uses
stable `PFxxxx` code identifiers for application and Studio diagnostics.
`PaperForge.inspect_document/1` returns a stable inventory map, and
`PaperForge.render/2` returns `{:ok, pdf, diagnostics}` for a completed binary
plus measurements. New diagnostic keys may be added in patch releases; existing
keys keep their meaning throughout `1.x`.

## Supported runtime contract

The supported Elixir and OTP versions are declared in `mix.exs` and CI. A
future release may drop an end-of-life runtime only in a minor release and will
record that change in the changelog.

## Optional external validation

PaperForge does not shell out while generating PDFs or while signing with the
default PKCS#8 provider. The optional PKCS#12/PFX loader uses `openssl` only
when explicitly selected. Development and CI may run
`pdfinfo`, `qpdf --check`, and VeraPDF when those tools are installed.

## Production execution

`PaperForge.Concurrent` provides bounded in-process execution. Durable queues,
distributed retries, storage, and scheduling remain application concerns so
PaperForge does not require Oban or another job system. See
[`PRODUCTION.md`](PRODUCTION.md) for supported integration patterns, resource
budgets, incremental file output, and deployment sizing.
