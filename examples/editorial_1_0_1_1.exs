{:ok, source} = PaperForge.Declarative.load(Path.join(__DIR__, "editorial_1_0_1_1.paperforge"))
{:ok, document, report} = PaperForge.Declarative.render(source)
path = Path.expand("../output/pdf/editorial-1-0-1-1.pdf", __DIR__)
File.mkdir_p!(Path.dirname(path))
PaperForge.write!(document, path)
3 = report.pages
3 = PaperForge.page_count(PaperForge.open!(path))
IO.puts(path)
