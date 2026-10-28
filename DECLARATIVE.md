# Declarative Documents

PaperForge 1.4 compiles versioned `.paperforge` JSON templates into the same
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
| `forms` | Standard AcroForm fields applied after pagination |

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
cycle-checked, deterministic, and independent of Elixir source. The release
showcase keeps its composed components inline so one file demonstrates the
complete format.

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
- `html`, `markdown`, and `math`
- `equation`, `equation_reference`, and `bibliography`
- `footnote` and `endnotes`
- `annotation` for common PDF review annotations
- `qr_code` and `barcode`
- `spacer`, `separator`, and `page_break`
- `table_of_contents` and `reference`

Block-specific values use `content` or their named fields: `columns` and
`rows` for tables, `cells` for grids, and `paragraphs` for columns. Common
options live under `options` and compile to existing `PaperForge.Flow` options.
Page templates accept either one numeric `margins` value or individual
`top`, `right`, `bottom`, and `left` values in a margins object.

`rich_text` runs accept `font`, `size`, `color`, `weight`, and `style` options.
Use `"weight": "bold"` for genuine built-in or registered bold font variants;
the renderer measures each run with the same variant used in the PDF.

Charts accept `[label, value]` pairs and `options.chart_type` values `bar`,
`line`, `area`, `scatter`, `pie`, or `donut`. Use `color` for a single-series
accent or `colors` for a reusable palette. `show_values`, `line_width`,
`point_radius`, and `inner_radius` control the marks. `background_color` and
`label_color` let each chart panel follow the document theme without leaving
the declarative format. `chart_padding` reserves interior space around marks,
value labels, and axis labels; it defaults to `12` points.

### Chart scales and document sections (1.5)

Cartesian charts include zero and support negative values. `show_axes` and
`show_grid` default to true. `tick_count` (2–10, default 5) is a target: the
renderer selects readable numeric intervals. `y_min` and `y_max` must contain
zero and every value. `value_decimals` (0–6), `value_prefix`, `value_suffix`,
`label_size`, `value_size`, `title_size`, `title`, and `subtitle` control labels.
Dense categories sample labels while preserving every data point. Scatter uses
categorical X positions, not numeric X/Y pairs. Pie/donut data must be
nonnegative; empty and all-zero series display explicit messages. Disable
`show_legend` to center a radial chart without its legend. `show_values: false`
hides numeric labels, including values and percentages in radial legends.
An undersized plot or legend raises an error instead of overflowing.

`group` contains `blocks` and accepts `options.keep_together`. `section` contains
`blocks`, an optional `name`, and `options.page_options` (size, margins, header,
footer). Nested children obey the same validation and compilation budgets as
ordinary blocks. For a full-bleed cover followed by paginated body pages, see
[`examples/atlas_2026.paperforge`](examples/atlas_2026.paperforge). Navigation
supports `levels`, `level_styles` keyed by heading level, and
`single_line_entries` to flatten explicit newlines in contents entries.

### Imported Markup And Math

`html` accepts the documented safe HTML/CSS subset and `markdown` accepts
CommonMark. Both compile into ordinary measured blocks. `math` accepts a JSON
Math AST containing `symbol`, `row`, `fraction`, `root`, `matrix`,
`superscript`, `subscript`, or `integral` nodes.

HTML tables can style `table`, `th`, and `td` with colors, backgrounds,
typography, padding, line height, borders, horizontal and vertical alignment,
and width. `tr:nth-child(even)` provides deterministic row striping. Complex
browser layout and scripting remain outside the import contract.

The same safe subset supports simple and compound element/class/ID selectors,
inline declarations, built-in PDF font families, text transformation,
backgrounds, borders, padding, sizing, vertical margins, list markers,
hyphenation, widow/orphan controls, hidden content, paged-media breaks, and
image fit and position. Use `strict_css: true` to reject unsupported
declarations during template validation.

Use `equation` with the same `ast` field for automatic numbering and a stable
`equation-N` destination. `equation_reference` accepts `number` and can format
the final page through `options.text`. `bibliography` accepts string entries or
objects containing `author`, `title`, `publisher`, and `year`.

```json
[
  {
    "type": "equation",
    "ast": {
      "fraction": {
        "numerator": {"symbol": "1"},
        "denominator": {"symbol": "2"}
      }
    }
  },
  {"type": "equation_reference", "number": 1},
  {
    "type": "bibliography",
    "entries": [
      {"author": "PaperForge Contributors", "title": "Scientific authoring", "year": 2026}
    ]
  }
]
```

### Forms And Annotations

Root-level `forms` are applied after pagination so their one-based `page` and
PDF-coordinate `rect` values remain stable. Supported types are `text`,
`checkbox`, `button`, `radio`, `list`, `combo`, and `signature`. Choice fields
accept `options`; calculated fields accept `sum`, `product`, or `average` over
named fields. Radio fields declare one or more page/rect/value choices.
`origin` defaults to `bottom_left`, matching native PDF coordinates. Set it to
`top_left` when aligning fields with flowing content authored from the visual
top-left page origin.

```json
{
  "forms": [
    {
      "type": "text",
      "name": "reviewer",
      "page": 1,
      "rect": [72, 90, 280, 111],
      "border_radius": 5,
      "border_width": 0.75,
      "border_color": "0.65 0.72 0.75"
    },
    {
      "type": "radio",
      "name": "decision",
      "value": "approve",
      "choices": [
        {"page": 1, "rect": [72, 50, 90, 68], "value": "approve"},
        {"page": 1, "rect": [110, 50, 128, 68], "value": "revise"}
      ]
    }
  ]
}
```

The rectangle controls the physical field size. Compact web-like controls can
use heights around 18-21 points for text and 11-14 points for checkboxes.
Appearance options include `background_color`, `border_color`, `border_width`,
`border_radius`, `check_color`, and `check_width`. Text appearances also accept
`font` (a built-in or declared font), positive `font_size`, `text_color`,
`text_align` (`left`, `center`, `right`), and non-negative `padding`. Single-line
values shrink to fit their rectangle without changing the stored field value.
Buttons center their labels by default. Radio controls are circular, and strokes
are inset so their borders remain visible. Use a font covering the intended
characters for non-Latin visible values; field names and tooltips use PDF Unicode
strings independently of the appearance font.

Math blocks accept `align: "center"` or `"right"` to position the measured
expression within its layout column. The default remains left-aligned.

The eight-page [Lumen visual notebook](examples/lumen_visual_2026.paperforge)
combines imported narrative, charts, tables, centered formulas, notes and a
symmetrical interactive review form. Generate and verify it with:

```sh
mix run examples/lumen_visual_2026.exs
python3 examples/verify_lumen.py  # optional independent check; requires pypdf
```

An `annotation` block accepts `annotation_type`: `note`, `highlight`,
`underline`, `strikeout`, `stamp`, `free_text`, `square`, `circle`, `ink`, or
`file_attachment`.
Geometry and annotation metadata live under `options`. Attachment bytes must
come from validated template data or a trusted component; templates do not
gain arbitrary filesystem access.

PDF page import and document composition are intentionally application-level
operations through `PaperForge.Interoperability`. They change the complete
document graph and can open external files, so `.paperforge` does not provide a
block that reads or combines arbitrary PDFs.

## Imports, Resources, And Limits

Embedded fonts can be declared without executable template code:

```json
{
  "fonts": {
    "body": {"path": "assets/NotoSans-Regular.ttf", "subset": true},
    "body_bold": {"source": "app:noto-sans-bold", "subset": true}
  },
  "font_fallbacks": {"body": ["symbols"]},
  "document": {"default_font": "body"}
}
```

`path` is confined to the template root. Logical `source` names are resolved
only from trusted `font_sources:` supplied by the host application, which lets
desktop or server products bundle fonts without exposing arbitrary files.

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

## Security, Protection, And Compliance

Templates may declare output policy without embedding credentials:

```json
{
  "security": {
    "algorithm": "aes_256",
    "permissions": {
      "print": "high_resolution",
      "copy": false,
      "modify": false,
      "extract": false
    }
  },
  "signature": {
    "algorithm": "ps256",
    "reason": "Contract approval",
    "location": "Monterrey, Mexico",
    "contact_info": "legal@example.com"
  },
  "protection": {
    "watermark": {
      "text": "CONFIDENTIAL",
      "opacity": 0.12,
      "color": "#64748B",
      "angle": 35
    },
    "policy": {
      "allowed_uri_schemes": ["https", "mailto"],
      "allowed_hosts": ["documents.example.com"],
      "allow_attachments": true,
      "max_attachments": 5,
      "max_attachment_bytes": 5000000,
      "allowed_attachment_mimes": ["application/pdf", "text/csv"]
    }
  },
  "compliance": {
    "profiles": ["pdf_ua_1"],
    "language": "en-US",
    "title": "Accessible contract"
  }
}
```

`security` may contain `user_password` and `owner_password`, allowing a
template to produce an encrypted PDF without Elixir write options:

```json
{
  "security": {
    "algorithm": "aes_256",
    "user_password": "reader-secret",
    "owner_password": "owner-secret",
    "permissions": {"print": "high_resolution", "copy": false}
  }
}
```

Embedded passwords are plain text in the template. Keep them only in
controlled templates or examples. For shared templates and production secret
rotation, omit them from `.paperforge` and pass them at the final output
boundary instead. Runtime options override embedded values:

```elixir
PaperForge.Declarative.write(template, data, "contract.pdf",
  security: [
    user_password: "reader-secret",
    owner_password: System.fetch_env!("PDF_OWNER_PASSWORD")
  ],
  signature: [
    certificate:
      {:pkcs8,
       key_path: "secrets/signing-key.pem",
       cert_path: "secrets/signing-chain.pem",
       password: System.get_env("PDF_KEY_PASSWORD")}
  ]
)
```

The default PKCS#8 provider runs entirely in Elixir/OTP. Selecting
`{:pkcs12, path, options}` is optional and invokes OpenSSL at runtime. A custom
`provider:` can integrate HSM or cloud signing without changing the template.
Keeping credentials at write time prevents a compiled template, cache entry, source file, or ordinary data
map from retaining secrets. PDF/A profiles require `icc_profile` and cannot
be combined with encryption. Use `PaperForge.Compliance.validate/2` and an
external validator such as VeraPDF for release certification.

## Trust Boundary

The JSON parser and variable engine are safe for untrusted input data. Template
authors still control links and document complexity. Keep templates in an
application-controlled repository or authenticated template system, configure
an explicit resource root, retain the built-in limits, and use normal
application job isolation.

## Complete Example

Render the self-contained declarative report with the CLI or application API:

```bash
mix paper_forge.validate examples/paper_forge_1_4_showcase.paperforge
```

The template at `examples/paper_forge_1_4_showcase.paperforge` contains default
data, inline reusable components, themes, navigation, a chart, a table, QR
output, security policy, protection policy, and tagged-PDF preparation. The
companion `examples/paper_forge_1_4_showcase.exs` demonstrates the same report
domain with full low-level visual control.

### Compact presentation and reusable styles

Use `design_system.styles` to share presentation settings. Styles support
`extends`; child styles override their parent, and explicit element options
have the final say. Cycles and missing parent styles fail during compilation.
Form fields now accept a named `style` as well as their individual appearance
options. Fonts registered by the template can also be used inside styles.

```json
{
  "design_system": {
    "tokens": {"controls": {"height": 22}, "type": {"field": 9.5}},
    "styles": {
      "field": {
        "font_size": "$type.field", "padding": 6,
        "text_color": "#183B45", "border_color": "#DCE6E6",
        "border_width": 0.6, "border_radius": 2
      },
      "amount": {"extends": "field", "text_align": "right"},
      "table": {
        "size": 9, "row_height": 25, "padding": 6,
        "cell_line_height": 12, "cell_valign": "middle",
        "borders": ["bottom"], "line_width": 0.35,
        "stroke_color": "#DCE6E6"
      }
    }
  },
  "forms": [{
    "type": "text", "name": "amount", "page": 1,
    "origin": "top_left", "x": 52, "y": 180,
    "width": 180, "height": "$controls.height",
    "style": "amount", "value": "€ 125,000"
  }]
}
```

This is a configuration fragment; add the document's `version` and `blocks`.
Form geometry accepts either `rect` or `x`, `y`, `width`, `height`, never both.
The latter values may reference design tokens. Resolved width and height must be
positive numbers. Coordinates and dimensions are PDF points (72 points = 1 inch).
The field's rectangle controls its physical size; `font_size` controls its text.
`border_width: 0` removes the stroke instead of drawing a PDF hairline.
Root forms use explicit page coordinates, so leave room for them in page content.

| Element | Controls |
| --- | --- |
| Forms | `style`, `x/y/width/height` or `rect`, `font`, `font_size`, `padding`, `text_align`, text/background/border/check colors, border/check widths, radius |
| Tables | `width`, `column_widths`, `size`, `row_height`, `cell_line_height`, `padding`, `cell_align`, `cell_valign`, `borders`, `line_width`, `stroke_color`, body/header/stripe colors |
| Charts | `width`, `height`, `chart_padding`, `title_size`, `subtitle_size`, `title_gap`, `label_size`, `value_size`, `legend_size`, `legend_gap`, `legend_marker_size`, `radial_size`, `inner_radius`, colors and line/point sizes |
| Math / equations | `size`, `align`, `height`, spacing and color; `heading_options` controls the equation title independently |
| Bibliography | Entry `size`, `line_height`, color and spacing; `heading_options` controls the section heading |
| Footnotes | `size`, `font`, `line_height`, color, `show_separator`, `separator_height`, `separator_length`, `separator_width`, `separator_color` |

Table `row_height` is a minimum: wrapping can require taller rows. Use `borders:
"none"` or a list of `top`, `right`, `bottom`, `left`; individual cell borders
still override the table setting. `cell_valign` also applies to structured cells
without their own vertical alignment. `stroke_color` controls table dividers.

For charts, `radial_size` is the maximum diameter of a pie/donut in points; it is
bounded by the space available for the plot and legend. Legend typography is
independent of axis labels. Insufficient space still fails explicitly rather
than silently hiding content. Existing defaults are retained when options are
omitted.

```json
{
  "type": "equation",
  "ast": {"symbol": "R = 73.67"},
  "options": {
    "size": 16, "align": "center",
    "heading_options": {"size": 11, "color": "#557177", "space_after": 10}
  }
}
```

The Lumen source includes `compact` and `comfortable` themes. Both remain
interactive; all visual settings live in the `.paperforge` file:

```sh
mix run examples/lumen_visual_2026.exs compact
mix run examples/lumen_visual_2026.exs comfortable
```

Change `tokens.controls.height` to resize text/choice fields together, or change
an individual field's height. Change shared styles to tune all tables, charts,
formulas or notes. Explicit per-element options override those shared settings.

### Math and Scientific typography

Math now defaults to **11-point Times Roman**. Geometry scales with `size`,
including fraction padding and rules, radicals, integral strokes/limits,
script gaps and matrix brackets. Rows align on a mathematical axis rather than
vertically centering unrelated bounding boxes. Superscripts remain within the
measured box, and each matrix row reserves only its own required height.

Equation labels default to 9.5 points; bibliography headings default to 12.
Override `heading_options` independently of expression `size`. Explicit sizes
are still honored. Named math styles are resolved before measuring the AST.

```sh
mix run examples/math_scientific_visual.exs
```

The corresponding `examples/math_scientific_visual.paperforge` contains fractions,
powers, roots, integrals, mixed-height matrices and nested expressions, followed
by a direct 9/11/14-point comparison. This remains a native measured Math AST;
it does not implement full TeX typesetting or arbitrary mathematical font shaping.

### Watermark fitting and placement (1.5)

`protection.watermark` accepts `margin` (36 points by default), `fit` (true),
`offset_x` and `offset_y` (zero). `size` is the maximum font size when fitting
is enabled. Fitting uses the rotated text bounds inside the page crop box;
positive offsets move right/up in PDF coordinates. Set `fit: false` for an
intentional oversized watermark. Existing `angle`, `color` and `opacity`
controls remain available. Text uses Helvetica Bold with WinAnsi coverage.

See `examples/design_protection_review.paperforge` for a complete compact
example using named styles, tokens, table rules and a restrained watermark.

### Runtime themes and token aliases

The template's `theme` is a default. An explicit application choice takes
precedence, without editing or duplicating the source:

```elixir
PaperForge.Declarative.render(template, data, theme: "comfortable")
PaperForge.Declarative.render(template, data, theme: nil) # base design system
```

Tokens can refer to other tokens, including nested paths (`"$type.body"`).
Missing references, cycles and chains exceeding 32 references fail compilation.
Watermark presentation properties also accept token references; watermark text
remains literal/interpolated text, so a label such as `$100` is not a token.

Run `mix run examples/design_protection_review.exs` to generate compact and
comfortable PDFs from one template. The runner reopens both files and verifies
their page count and protection fingerprint.

### Navigation and endnote presentation (1.0 / 1.1 review)

`table_of_contents` accepts `heading_options` for its title independently of
entry `size`, `color`, `line_height`, `space_after` and `level_styles`.
Leader counts now use real font metrics and the available page/column width;
`indent` works without supplying an absolute `x`. Custom entry formatters keep
full control of their text.

`endnotes` retains explicitly supplied `content` entries (`number` / `text`).
With no entries, it collects preceding footnotes as before. Entry options now
preserve font, size, color, width, line height and spacing. `heading_options`
controls the heading independently. Defaults are a 12-point heading and
9-point entries, with proportional line height.

Generate the complete native example with:

```sh
mix run examples/editorial_1_0_1_1.exs
```

Its three pages cover the linked index, a footnote and explicit endnotes.

### QR invitations supplied as data

A client only supplies `qr_code` (a UUID, URL or text); presentation remains in
`.paperforge`. See `examples/qr_invitation.paperforge` and its data-only runner.

```json
{"type":"qr_code","content":"{{qr_code}}","options":{
  "size":108,"align":"center","level":"h","quiet_zone":4,
  "color":"#183B45","background_color":"#FFFFFF","space_after":12
}}
```

Declare `qr_code` as a required string variable. `size` is the entire square in
PDF points (72 points = 1 inch), including the quiet zone. It can also be a typed
variable (`"{{qr_size}}"`) or design token. Alignment is `left`, `center`, or
`right`; explicit `x` overrides alignment. Flow chooses `y` and reserves the
square's height; use `Page.qr_code/3` for explicit x/y coordinates. The native API
supports both page origins. A size larger than the flow's available width fails
rather than overlapping the margin.

`level` accepts `l`, `m` (default), `q`, `h`. `quiet_zone` accepts 4–32 modules.
The default background is white; native `background_color: nil` is transparent.
Legacy `width`/`height` remain supported: their minimum is the square size,
with 120-point defaults. Explicit `size` takes precedence. Colors, payload length
and physical printed size affect scan reliability; keep strong contrast and
verify your final print size. Empty payloads are rejected. The QR contains the
supplied value verbatim; issuance, redemption and duplicate-use checks belong to
the application.

For repeated rendering, load the template once outside the request loop and
supply new data to `PaperForge.Declarative.render/3`. Use bounded concurrency
(`PaperForge.Concurrent.run/3`) rather than launching an unbounded task per PDF.
Local QR throughput measurements and their limitations are recorded in
`benchmarks/results/qr-optimization/comparison.md`.

## Configurable visual primitives

See [Visual blocks](VISUAL_BLOCKS.md) for containers, rows, columns, block grids,
overlays, vector shapes and icons, badges, linked buttons and clipped images.
The four-page example lives in `examples/visual_blocks.paperforge`.
Compositions are measured once and paginate atomically; oversized compositions
return an error. Existing flow blocks remain suitable for multipage content.
