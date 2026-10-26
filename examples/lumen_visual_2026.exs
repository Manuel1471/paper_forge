# All design and sample data live in the .paperforge source.
{:ok, source} = PaperForge.Declarative.load(Path.join(__DIR__, "lumen_visual_2026.paperforge"))
theme = List.first(System.argv()) || Map.get(source, "theme", "compact")
unless theme in ["compact", "comfortable"], do: raise("Use compact or comfortable")
{:ok, document, layout} = PaperForge.Declarative.render(Map.put(source, "theme", theme))
suffix = if theme == "compact", do: "", else: "-#{theme}"
output = Path.expand("../output/pdf/lumen-visual-2026#{suffix}.pdf", __DIR__)
File.mkdir_p!(Path.dirname(output))
PaperForge.write!(document, output)
reopened = PaperForge.open!(output)
8 = PaperForge.page_count(reopened)
7 = map_size(PaperForge.AcroForm.export_data(reopened))
%{"revisor_ñ" => "Lucía Peña", "país" => "MX", "estado" => "aprobado"} = PaperForge.AcroForm.export_data(reopened)
IO.puts("Lumen: #{layout.pages} pages; fields and values verified. #{output}")
