defmodule PaperForge.DocumentationPackageTest do
  use ExUnit.Case, async: true

  test "ships declarative guides, schema, and maintained release examples" do
    project = PaperForge.MixProject.project()
    package_files = project |> Keyword.fetch!(:package) |> Keyword.fetch!(:files)
    docs_extras = project |> Keyword.fetch!(:docs) |> Keyword.fetch!(:extras)

    assert "priv" in package_files
    assert "examples" in package_files
    assert "PAPERFORGE_TEMPLATES.md" in package_files
    assert "PAPERFORGE_TEMPLATES.md" in docs_extras
    assert "PHOENIX.md" in package_files
    assert "PHOENIX.md" in docs_extras

    assert File.exists?("priv/paperforge.schema.json")
    assert File.exists?("examples/paper_forge_1_3_showcase.paperforge")
    assert File.exists?("examples/paper_forge_1_3_showcase.exs")

    template = File.read!("examples/paper_forge_1_3_showcase.paperforge")
    assert template =~ ~s("security")
    assert template =~ ~s("protection")
    assert template =~ ~s("pdf_ua_1")
  end

  test "ships a discoverable Phoenix integration guide" do
    readme = File.read!("README.md")
    guide = File.read!("PHOENIX.md")

    assert readme =~ "[Phoenix Quick Start](#phoenix-quick-start)"
    assert readme =~ "[`PHOENIX.md`](PHOENIX.md)"
    assert guide =~ "PaperForge With Phoenix"
    assert guide =~ "PaperForge.Declarative.render"
    assert guide =~ "Task.Supervisor"
    assert guide =~ "Optional Oban Worker"
    assert guide =~ "Future Visual Authoring"
  end

  test "README links the plain-language and technical template guides" do
    readme = File.read!("README.md")
    guide = File.read!("PAPERFORGE_TEMPLATES.md")

    assert readme =~ "[`PAPERFORGE_TEMPLATES.md`](PAPERFORGE_TEMPLATES.md)"
    assert readme =~ "[`DECLARATIVE.md`](DECLARATIVE.md)"
    assert guide =~ "Create PaperForge Documents Without Writing Elixir"
    assert guide =~ "mix paper_forge.validate"
    assert guide =~ "examples/paper_forge_1_3_showcase.paperforge"
  end
end
