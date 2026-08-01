# Create PaperForge Documents Without Writing Elixir

This guide explains how to build reusable documents with `.paperforge` files.
You do not need to understand PDF internals or learn Elixir to edit text,
colors, sections, conditions, or components.

## The Main Idea

A document has three simple parts:

1. The template decides what appears and in which order.
2. The data contains names, amounts, dates, and lists that change.
3. Components store reusable parts of the design.

For example, an invoice can always use the same header and table while receiving
a different customer and product list each time.

```text
template.paperforge + data.json = document.pdf
```

## Why Use Templates?

- The design stays separate from customer or report information.
- One template can generate hundreds of different documents.
- Visual changes are made in one place.
- Components can be shared by invoices, reports, and contracts.
- PaperForge checks the data before creating the PDF.
- Templates cannot execute code embedded in the file.

## An Easy Folder Structure

A small organization can begin with this structure:

```text
documents/
├── annual_report.paperforge
├── invoice.paperforge
├── data/
│   ├── report_2027.json
│   └── invoice_1042.json
└── components/
    ├── company_header.paperforge
    ├── metric_line.paperforge
    └── signature.paperforge
```

The names can be changed. The important part is keeping documents, their data,
and their components organized together.

## Create A Minimal Template

The following file receives a name and displays a heading:

```json
{
  "version": "1",
  "variables": {
    "customer": {"type": "string", "required": true}
  },
  "blocks": [
    {"type": "heading", "text": "Welcome, {{customer}}"},
    {"type": "paragraph", "text": "Thank you for working with us."}
  ]
}
```

`{{customer}}` marks the place where PaperForge inserts the received name.

The data can be stored in a separate file:

```json
{
  "customer": "Lumen Atlas"
}
```

## What Are Blocks?

Blocks are the pieces that make up a page. The most common blocks are:

- `heading`: a title or heading.
- `paragraph`: a paragraph of text.
- `image`: an image.
- `table`: a table.
- `list`: a list.
- `spacer`: space between content.
- `separator`: a dividing line.
- `page_break`: start a new page.
- `qr_code`: a QR code.
- `component`: a reusable design element.

Each block can have options such as size, color, spacing, or style.

## Create A Reusable Component

A component is a document part that receives information and produces content.
This file represents one performance metric:

```json
{
  "version": "1",
  "kind": "component",
  "name": "metric_line",
  "props": {
    "label": {"type": "string", "required": true},
    "value": {"type": "string", "required": true}
  },
  "blocks": [
    {
      "type": "paragraph",
      "text": "{{label}}: {{value}}",
      "options": {"style": "metric"}
    }
  ]
}
```

`props` describes the information required by the component. If a property
marked as `required` is missing, PaperForge reports the problem before creating
the PDF.

## Use The Component In A Document

First add its file to `components`:

```json
{
  "version": "1",
  "components": ["components/metric_line.paperforge"],
  "blocks": [
    {
      "component": "metric_line",
      "props": {
        "label": "Revenue",
        "value": "$562M"
      }
    }
  ]
}
```

A component can also import and use other components. This makes it possible to
build a complete section from smaller headings, metrics, tables, and notes.

## Repeat Content From A List

When the data contains several metrics, the design does not need to be repeated:

```json
{
  "for": "metric in metrics",
  "blocks": [
    {
      "component": "metric_line",
      "props": {
        "label": "{{metric.label}}",
        "value": "{{metric.value}}"
      }
    }
  ]
}
```

PaperForge creates one line for every item in `metrics`.

## Show Content Only When Needed

Conditions can display warnings, discounts, or optional sections:

```json
{
  "if": {
    "left": "{{growth}}",
    "operator": "lt",
    "right": 0
  },
  "then": [
    {"type": "paragraph", "text": "Growth requires attention."}
  ]
}
```

In this example, the message appears only when `growth` is below zero.

## Leave Customizable Spaces

A component can provide spaces called slots. The component decides where the
space appears, and each document decides what to place inside it.

Inside the component:

```json
"slots": {
  "details": {"required": false}
},
"blocks": [
  {"type": "heading", "text": "{{title}}"},
  {"slot": "details"}
]
```

When using the component:

```json
"slots": {
  "details": [
    {"type": "paragraph", "text": "Additional information."}
  ]
}
```

## Variants

Variants allow a component to have different presentations, such as `compact`,
`featured`, or `warning`, without creating several nearly identical files.

```json
"variants": {
  "compact": {
    "blocks": [
      {"type": "paragraph", "text": "{{label}}: {{value}}"}
    ]
  }
}
```

Select the variant when using the component:

```json
{
  "component": "metric_line",
  "variant": "compact",
  "props": {"label": "Margin", "value": "18.4%"}
}
```

## Shared Colors And Styles

Styles prevent repeated sizes and colors in every block:

```json
"design_system": {
  "styles": {
    "title": {"size": 26, "color": "#17324d"},
    "body": {"size": 10, "color": "#243746"},
    "positive": {"size": 11, "color": "#078c7d"}
  }
}
```

Then select the style from a block:

```json
{
  "type": "paragraph",
  "text": "+13.2% growth",
  "options": {"style": "positive"}
}
```

## Check A Template Before Generating

You can check a template without creating a PDF:

```bash
mix paper_forge.validate documents/annual_report.paperforge \
  documents/data/report_2027.json \
  --root documents
```

If something is missing, PaperForge shows where the problem occurred:

```text
documents/data/report_2027.json:4:3 $.data.company [required] required variable is missing
```

This message means the data does not contain `company`. It also identifies the
file, line, column, and exact data path so the value can be found quickly.

You can also check a component by itself without preparing data:

```bash
mix paper_forge.validate documents/components/metric_line.paperforge \
  --root documents
```

## Recommended Workflow

1. Begin with a small template and a small data file.
2. Generate the PDF and review the content order.
3. Move repeated colors and sizes into styles.
4. Turn repeated sections into components.
5. Store each important component in its own file.
6. Validate the template before publishing or using it in production.
7. Test short, long, empty, and large collections of data.

## What May Still Need Technical Support?

Most business documents can be built with `.paperforge` blocks and components.
A design that draws shapes at very specific coordinates or performs an operation
that does not yet have a declarative block may require a component registered by
the application.

That code is optional and controlled by the application maintainer. Template
authors cannot execute arbitrary functions from a `.paperforge` file.

## Included Example

Review `examples/paper_forge_1_3_showcase.paperforge`. It is a self-contained
report with default data, reusable inline components, themes, chart, table,
navigation, QR output, security policy, and accessible tagged-PDF preparation.
`examples/paper_forge_1_3_showcase.exs` shows the same report domain with full
coordinate-level drawing control.

For every available option and detailed security information, read
`DECLARATIVE.md`.
