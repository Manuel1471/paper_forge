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

## Supported runtime contract

The supported Elixir and OTP versions are declared in `mix.exs` and CI. A
future release may drop an end-of-life runtime only in a minor release and will
record that change in the changelog.

## Optional external validation

PaperForge does not shell out while generating PDFs. Development and CI may run
`pdfinfo`, `qpdf --check`, and VeraPDF when those tools are installed.
