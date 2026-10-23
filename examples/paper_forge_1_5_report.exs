Code.require_file("support/atlas_report.ex", __DIR__)
Code.require_file("support/atlas_verification.ex", __DIR__)

alias PaperForge.Examples.{AtlasReport, AtlasVerification}

output = Path.expand("../output/pdf/atlas-2026", __DIR__)
File.mkdir_p!(output)
{document, layout} = AtlasReport.build()
path = Path.join(output, "atlas-2026-report.pdf")
PaperForge.write!(document, path)
reopened = PaperForge.open!(path)
verification = AtlasVerification.verify!(reopened, layout)

transformation =
  AtlasVerification.transformed_extract!(reopened, Path.join(output, "atlas-2026-extract.pdf"))

verification = Map.put(verification, "transformation_checks", transformation)
File.write!(Path.join(output, "verification.json"), Jason.encode!(verification, pretty: true))
File.write!(Path.join(output, "routes.json"), Jason.encode!(AtlasReport.routes(), pretty: true))
IO.puts("Atlas: #{layout.pages} pages, 120 routes, all verification checks passed.")
IO.puts("Output: #{output}")
