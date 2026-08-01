# Declarative Documents

PaperForge 1.2 compiles versioned `.paperforge` JSON templates into the same
`PaperForge.Flow` Layout IR used by the Elixir authoring API. Templates contain
data only: the compiler does not evaluate Elixir expressions or arbitrary
functions.

## Lifecycle

```text
.paperforge JSON
|-- parse
|-- validate template and input data
|-- resolve design library, theme, and layout
|-- expand variables, conditions, loops, and components
|-- compile PaperForge.Flow Layout IR
`-- paginate and render PDF
```

Use `parse/1` for JSON already in memory, `load/1` for a file, `validate/2` to
check a template and its input, `compile/3` to inspect Layout IR, and `render/3`
to produce a document.

```elixir
with {:ok, template} <- PaperForge.Declarative.load("invoice.paperforge"),
     :ok <- PaperForge.Declarative.validate(template, invoice_data),
     {:ok, document, report} <- PaperForge.Declarative.render(template, invoice_data),
     :ok <- PaperForge.write(document, "invoice.pdf") do
  {:ok, report.pages}
end
```

## Root Format

Every template requires `"version": "1"`.

| Field | Purpose |
| --- | --- |
| `version` | Declarative format version; currently `"1"` |
| `variables` | Input schema with types, required flags, and defaults |
| `imports` / `libraries` | Design libraries merged before this template |
| `includes` | Template fragments whose blocks are inserted before local blocks |
| `components` | Reusable `.paperforge` component files loaded by this document |
| `document` | Options passed to `PaperForge.new/1` |
| `metadata` | Dynamic PDF metadata |
| `layout_options` | Options passed to the unified layout engine |
| `page_templates` | Named page templates available during rendering |
| `design_system` | Inline tokens, styles, components, layouts, and themes |
| `theme` | Theme selected from the resolved design system |
| `layout` | Shared layout selected from the resolved design system |
| `blocks` | Ordered declarative document content |

## Variables And Validation

Supported types are `string`, `number`, `integer`, `boolean`, `list`, `map`,
and `any`. Schemas support `min`, `max`, `min_length`, `max_length`, `pattern`,
`enum`, recursive list `items`, map `properties`, `required_properties`, and
`additional_properties`. String formats include `url`, `color`, and `file`.

```json
{
  "variables": {
    "customer": {"type": "map", "required": true},
    "items": {"type": "list", "required": true},
    "show_terms": {"type": "boolean", "default": true}
  }
}
```

Use `{{customer.name}}` to interpolate a nested value. An interpolation that
occupies the entire JSON string preserves the original value type, allowing a
list such as `{{items}}` to become table rows. Interpolation inside a longer
string converts the value to text.

Unknown template properties are rejected. Pass `reject_unknown_data: true` to
reject undeclared input keys as well. Validation errors are
`PaperForge.Declarative.Error` structs containing `:code`, JSON `:path`,
`:message`, optional `:details`, and, when loaded from disk, the exact `:source`,
`:line`, and `:column`. Template errors point to the relevant `.paperforge`
property. CLI data errors point to the relevant property in the supplied JSON
data file. Input data can be untrusted; it is never converted to executable code.

## Conditions

```json
{
  "if": "show_terms",
  "then": [{"type": "paragraph", "text": "Payment is due in 30 days."}],
  "else": [{"type": "paragraph", "text": "Terms are available on request."}]
}
```

Values other than `null`, `false`, `0`, an empty string, or an empty list are
truthy.

Object expressions support `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `contains`,
`empty`, `and`, `or`, and `not`:

```json
{
  "if": {"left": "{{growth}}", "operator": "lt", "right": 0},
  "then": [{"type": "paragraph", "text": "Growth requires attention."}]
}
```

## Loops

String and object syntax are supported:

```json
{
  "for": "item in items",
  "blocks": [
    {"type": "paragraph", "text": "{{item.name}} - {{item.total}}"}
  ]
}
```

```json
{"for": {"each": "items", "as": "item"}, "blocks": []}
```

## Components

Components are reusable block groups with optional defaults, validated prop
schemas, required props, named slots, nested content, and visual variants.
Props are merged into the current variable context for each component instance.

```json
{
  "design_system": {
    "components": {
      "metric": {
        "defaults": {"change": "No change"},
        "blocks": [
          {"type": "heading", "text": "{{value}}"},
          {"type": "paragraph", "text": "{{label}} / {{change}}"}
        ]
      }
    }
  },
  "blocks": [
    {
      "component": "metric",
      "props": {"label": "Revenue", "value": "$12M", "change": "+8%"}
    }
  ]
}
```

Direct and indirect component cycles are rejected. Expansion is bounded to 64
nested levels, with configurable limits for blocks, loop iterations, table
rows, and input-data bytes.

### Components In Separate Files

A component can live entirely in its own `.paperforge` file:

```json
{
  "version": "1",
  "kind": "component",
  "name": "status_panel",
  "props": {
    "title": {"type": "string", "required": true},
    "status": {"type": "string", "enum": ["healthy", "attention"]}
  },
  "slots": {
    "details": {"required": false}
  },
  "variants": {
    "compact": {
      "blocks": [
        {"type": "paragraph", "text": "{{title}}: {{status}}"}
      ]
    }
  },
  "blocks": [
    {"type": "heading", "text": "{{title}}"},
    {"type": "paragraph", "text": "Status: {{status}}"},
    {"slot": "details"}
  ]
}
```

Load and use it from a document:

```json
{
  "version": "1",
  "components": ["components/status_panel.paperforge"],
  "blocks": [
    {
      "component": "status_panel",
      "variant": "compact",
      "props": {"title": "Platform", "status": "healthy"},
      "slots": {
        "details": [
          {"type": "paragraph", "text": "All regions are operating normally."}
        ]
      }
    }
  ]
}
```

Component files may list their own `components`, so a section can be assembled
from cards, labels, tables, and charts stored in other files. Loading is rooted,
cycle-checked, deterministic, and independent of Elixir source. See
`examples/components/metrics_section.paperforge`, which composes
`metric_line.paperforge`.

### Optional Trusted Components

Most reusable designs should use component files. For low-level operations that
cannot yet be expressed as declarative blocks, application-owned drawing code
can still be exposed safely through a registry. A template can invoke only
names explicitly registered by the host:

```elixir
registry =
  PaperForge.Declarative.Registry.new(resource_root: "templates")
  |> PaperForge.Declarative.Registry.component(
    :executive_cover,
    fn props, _slots -> build_cover(props) end,
    props: %{"company" => %{"type" => "string", "required" => true}},
    variants: [:default, :compact]
  )

PaperForge.Declarative.compile(template, data, registry: registry)
```

```json
{
  "component": "executive_cover",
  "variant": "compact",
  "props": {"company": "{{company}}"}
}
```

Registry renderers receive validated props and compiled slot flows. Template
content never selects an arbitrary module or function.

For offline CLI validation, declare the same component name and prop schema in
`design_system.components` with an empty `blocks` list. The CLI validates that
interface without executing application code; at runtime an explicitly
registered trusted renderer takes precedence.

## Design Systems

`PaperForge.DesignSystem` is an immutable library of tokens, styles, visual
components, layouts, and themes. Libraries can be created in Elixir, embedded
in a `.paperforge` file, or merged. The inline library takes precedence over
an externally supplied library.

```elixir
design_system =
  PaperForge.DesignSystem.new()
  |> PaperForge.DesignSystem.token(:brand, "#075985")
  |> PaperForge.DesignSystem.style(:title, %{"size" => 24, "color" => "$brand"})
  |> PaperForge.DesignSystem.theme(:executive, %{
    "styles" => %{"title" => %{"size" => 28}}
  })

PaperForge.Declarative.render(template, data,
  design_system: design_system,
  theme: :executive
)
```

Token references begin with `$` and support nested paths such as
`$colors.primary`. Color tokens accept `#RGB` and `#RRGGBB` values. Themes may
use `extends` and are resolved with cycle detection. Child values override
parent values through recursive map merging.

Layouts provide shared document options, layout options, metadata, page
templates, and default blocks. A template selects one with `"layout":
"annual_report"` and can override any layout field.

## Supported Blocks

- `heading`, `paragraph`, and `rich_text`
- `table`, `list`, `grid`, and `columns`
- `image`, `svg`, and `chart`
- `qr_code` and `barcode`
- `spacer`, `separator`, and `page_break`
- `table_of_contents` and `reference`

Block-specific values use `content` or their named fields: `columns` and
`rows` for tables, `cells` for grids, and `paragraphs` for columns. Common
options live under `options` and compile to existing `PaperForge.Flow` options.

## Imports, Resources, And Limits

`load/2` resolves `imports`, `libraries`, and `includes` relative to the source
file and rejects paths outside `root:`. Import cycles, count limits, and maximum
template bytes are checked before compilation.
`PaperForge.Declarative.Registry.new/1` applies the
same root policy to local images, fonts, attachments, and `format: "file"`
values; remote resources are restricted to configured URL schemes.

Default compilation limits are 10,000 blocks, 10,000 loop iterations, 50,000
table rows, and 10 MB of input data. Override them with `limits:` only after
setting application-level CPU, memory, and job timeouts.

## Validation, Schema, And Cache

Validate without rendering:

```bash
mix paper_forge.validate report.paperforge report.json --root templates
```

`PaperForge.Declarative.schema_path/0` returns the bundled Draft 2020-12 JSON
Schema. Version `"0"` documents using `schema` and `content` migrate to version
`"1"` through `migrate/1`; unsupported versions fail explicitly.

Every compiled result contains a deterministic SHA-256 `template_hash` and a
stable `template_id`. `compile_cached/3` uses a bounded process-local cache;
templates with registered Elixir components bypass it so closures and runtime
state are never cached accidentally.

## Trust Boundary

The JSON parser and variable engine are safe for untrusted input data. Template
authors still control links and document complexity. Keep templates in an
application-controlled repository or authenticated template system, configure
an explicit resource root, retain the built-in limits, and use normal
application job isolation.

## Complete Example

Run the bundled reusable report:

```bash
mix run examples/declarative_annual_report.exs
```

The fully declarative report lives in
`examples/declarative_annual_report.paperforge`. The larger
`examples/paper_forge_0_6_complete.paperforge` demonstrates declarative schema
and orchestration of an application-registered, trusted visual component; its
Elixir renderer contains the low-level custom drawing implementation.
