# Layout and expressions are entirely in the .paperforge source.
{:ok, source} = PaperForge.Declarative.load(Path.join(__DIR__, "math_scientific_visual.paperforge"))
{:ok, document, report} = PaperForge.Declarative.render(source)
output = Path.expand("../output/pdf/math-scientific-visual.pdf", __DIR__)
File.mkdir_p!(Path.dirname(output))
PaperForge.write!(document, output)
2 = PaperForge.page_count(PaperForge.open!(output))
IO.puts("Math + Scientific: #{report.pages} pages. #{output}")
