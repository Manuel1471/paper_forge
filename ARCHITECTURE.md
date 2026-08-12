# PaperForge Architecture

PaperForge is organized as a one-way document pipeline. Public APIs build
document intent; the lower layers turn that intent into native PDF objects and
then serialize them.

## Source Tree

The directory name describes the responsibility before a reader opens a file.
Public module names remain stable even when their source file belongs to a
different implementation layer.

```text
lib/paper_forge/
|-- authoring/   .paperforge, design systems, import, SVG, Math, science
|-- document/    document aggregate, PDF objects, metadata, geometry, streams
|-- resources/   fonts, images, registries, decoders, and font implementation
|-- layout/      Flow IR, measurement, pagination, block and layout errors
|-- rendering/   Page API, page compiler, page context, graphics commands
|-- pdf/          PDF syntax encoding, compression, parsing, and file writing
|-- security/     encryption, protection, compliance, forms, signatures
|-- runtime/      concurrency, telemetry, validation, and performance caches
`-- legacy/      maintained compatibility implementations
```

`lib/paper_forge.ex` is the small public facade. It is intentionally the only
top-level implementation file.

```text
Elixir API / .paperforge / HTML / Markdown / imported PDF
                         |
                         v
                Flow Layout IR or Page operations
                         |
                         v
                    Layout Engine
                         |
                         v
              PageCompiler and Graphics modules
                         |
                         v
              Document indirect-object graph
                         |
                         v
                  Serializer and Writer
                         |
                         v
                        PDF
```

## Layers

### Public authoring APIs

`PaperForge`, `PaperForge.Flow`, `PaperForge.Page`, and
`PaperForge.Declarative` are the supported entry points. `Flow` is the
measured, paginated layout API. `Page` is the exact-coordinate drawing API.
`.paperforge` templates, HTML, and Markdown compile into the same Flow model
where applicable.

### Layout

`PaperForge.Layout.Engine` expands components, resolves styles, measures
blocks, paginates placements, and renders logical pages. It must depend on the
Page API, but never on declarative parsing or import adapters.

### Page operation IR and rendering

`PaperForge.Page` stores high-level operations such as text, text boxes,
images, paths, links, and annotations. `PaperForge.PageCompiler` lowers these
operations through `PaperForge.Graphics.*`, registers resources, and produces
PDF content streams.

### Document core

`PaperForge.Document` is the aggregate root for PDF indirect objects and
document-wide registries. Its internal object-store implementation lives in
`PaperForge.Document.Objects`; public `Document` functions remain the stable
API. Fonts, images, navigation, metadata, and attachments are document-wide
resources.

### PDF encoding and output

`PaperForge.Serializer` encodes PDF primitives and streams as iodata.
`PaperForge.Writer` validates the completed object graph, writes objects and
cross-references, and produces a binary or an atomic file.

### Cross-cutting features

Forms, annotations, navigation, attachments, protection, compliance, and
signatures operate on the document graph or final output boundary. Runtime
concerns such as telemetry and concurrent rendering remain outside layout and
PDF encoding.

## Legacy helpers

`PaperForge.add_flow/4` and `PaperForge.add_table/4` are maintained for
existing applications. Their implementation is isolated under
`PaperForge.Legacy.*`; new documents should prefer `PaperForge.Flow` with
`PaperForge.layout/3`.

## Dependency Rules

- Authoring adapters compile into `Flow` or configure a `Document`.
- Layout produces `Page` values and does not parse templates.
- Page compilation may register document resources.
- The document core must not depend on layout or authoring adapters.
- Serializer and Writer only consume the completed document graph.

These rules let the implementation evolve without changing the stable 1.x
public surface.
