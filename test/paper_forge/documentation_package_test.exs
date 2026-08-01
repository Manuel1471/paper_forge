defmodule PaperForge.DocumentationPackageTest do
  use ExUnit.Case, async: true

  test "ships declarative guides, schema, and component examples" do
    project = PaperForge.MixProject.project()
    package_files = project |> Keyword.fetch!(:package) |> Keyword.fetch!(:files)
    docs_extras = project |> Keyword.fetch!(:docs) |> Keyword.fetch!(:extras)

    assert "priv" in package_files
    assert "examples" in package_files
    assert "PAPERFORGE_TEMPLATES.md" in package_files
    assert "PAPERFORGE_TEMPLATES.md" in docs_extras

    assert File.exists?("priv/paperforge.schema.json")
    assert File.exists?("examples/components/metric_line.paperforge")
    assert File.exists?("examples/components/metrics_section.paperforge")
  end

  test "README links the plain-language and technical template guides" do
    readme = File.read!("README.md")
    guide = File.read!("PAPERFORGE_TEMPLATES.md")

    assert readme =~ "[`PAPERFORGE_TEMPLATES.md`](PAPERFORGE_TEMPLATES.md)"
    assert readme =~ "[`DECLARATIVE.md`](DECLARATIVE.md)"
    assert guide =~ "Create PaperForge Documents Without Writing Elixir"
    assert guide =~ "mix paper_forge.validate"
    assert guide =~ "examples/components/metrics_section.paperforge"
  end
end
