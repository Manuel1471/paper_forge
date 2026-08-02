# Scientific Documents

PaperForge 1.4 adds a native Math AST and a scientific authoring layer. Math is
measured with layout blocks and rendered as PDF text and vector lines, so it
does not depend on TeX, MathJax, a browser, or raster images.

## Math AST

```elixir
alias PaperForge.{Flow, Math}

equation =
  Math.row([
    Math.integral(Math.symbol("0"), Math.symbol("1"),
      Math.superscript(Math.symbol("x"), Math.symbol("2")), "x"),
    Math.symbol("="),
    Math.fraction(Math.symbol("1"), Math.symbol("3"))
  ])

flow = Flow.new() |> Flow.math(equation, size: 18)
```

The AST supports symbols, rows, fractions, roots with optional indices,
matrices, superscripts, subscripts, and integrals with bounds. It is also
available in `.paperforge` through a `math` block and JSON Math AST.

## Numbering And References

`PaperForge.Scientific` maintains stable equation and citation counters around
a normal `PaperForge.Flow`. Equation destinations participate in the existing
multi-pass page-reference engine.

```elixir
scientific =
  PaperForge.Scientific.new()
  |> PaperForge.Scientific.equation(equation)
  |> PaperForge.Scientific.equation_reference(1)

{scientific, citation} =
  PaperForge.Scientific.cite(scientific, "paperforge-2026",
    author: "PaperForge Contributors",
    title: "Declarative PDF Authoring",
    year: 2026)

flow = scientific |> PaperForge.Scientific.bibliography() |> PaperForge.Scientific.to_flow()
```

Use the established `Flow.footnote/3`, `Flow.endnotes/2`,
`Flow.table_of_contents/2`, charts, SVG, and page-aware references alongside
the scientific builder. This provides numbered equations, bibliography
sections, figures, tables, notes, diagrams, and advanced navigation in one
layout pipeline.

The current Math AST is an authoring representation, not a TeX or MathML
parser. Advanced typographic stretching, OpenType MATH tables, and automatic
line breaking inside long equations remain future enhancements.
