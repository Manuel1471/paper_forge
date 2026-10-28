# All presentation lives in the .paperforge source. Runtime selects the theme.
{:ok, source} =
  PaperForge.Declarative.load(Path.join(__DIR__, "design_protection_review.paperforge"))

for theme <- ["compact", "comfortable"] do
  {:ok, document, report} = PaperForge.Declarative.render(source, %{}, theme: theme)
  path = Path.expand("../output/pdf/design-protection-#{theme}.pdf", __DIR__)
  File.mkdir_p!(Path.dirname(path))
  PaperForge.write!(document, path)
  reopened = PaperForge.open!(path)
  1 = PaperForge.page_count(reopened)
  :ok = PaperForge.Protection.verify_fingerprint(reopened)
  IO.puts("#{theme}: #{report.pages} page; fingerprint verified after reopening: #{path}")
end
