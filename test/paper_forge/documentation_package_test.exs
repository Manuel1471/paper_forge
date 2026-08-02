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
    assert "INTEROPERABILITY.md" in package_files
    assert "INTEROPERABILITY.md" in docs_extras
    assert "SCIENTIFIC.md" in package_files
    assert "SCIENTIFIC.md" in docs_extras

    assert File.exists?("priv/paperforge.schema.json")
    assert File.exists?("examples/paper_forge_1_4_showcase.paperforge")
    assert File.exists?("examples/paper_forge_1_4_showcase.exs")
    assert File.exists?("examples/investigacion.paperforge")
    assert File.exists?("examples/investigacion.exs")

    template = File.read!("examples/paper_forge_1_4_showcase.paperforge")
    assert template =~ ~s("security")
    assert template =~ ~s("protection")
    assert template =~ ~s("pdf_ua_1")
    assert template =~ ~s("type": "math")
    assert template =~ ~s("type": "markdown")
    assert template =~ ~s("type": "equation")
    assert template =~ ~s("forms")

    schema = "priv/paperforge.schema.json" |> File.read!() |> Jason.decode!()
    assert schema["properties"]["forms"]["items"]["$ref"] == "#/$defs/formField"
    assert schema["$defs"]["block"]["properties"]["annotation_type"]
    assert schema["$defs"]["block"]["properties"]["entries"]
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
    assert guide =~ "examples/paper_forge_1_4_showcase.paperforge"
  end

  test "README local files and section links remain valid and packaged" do
    readme = File.read!("README.md")
    project = PaperForge.MixProject.project()
    package_files = project |> Keyword.fetch!(:package) |> Keyword.fetch!(:files)
    docs = Keyword.fetch!(project, :docs)
    docs_extras = Keyword.fetch!(docs, :extras)

    links =
      ~r/\[[^\]]*\]\(([^)]+)\)/
      |> Regex.scan(readme, capture: :all_but_first)
      |> List.flatten()

    local_targets =
      links
      |> Enum.reject(&String.starts_with?(&1, ["http://", "https://", "mailto:", "#"]))
      |> Enum.map(&(String.split(&1, "#", parts: 2) |> hd()))
      |> Enum.uniq()

    assert Enum.all?(local_targets, &File.exists?/1)

    markdown_targets = Enum.filter(local_targets, &String.ends_with?(&1, ".md"))
    assert Enum.all?(markdown_targets, &(&1 in package_files))
    assert Enum.all?(markdown_targets, &(&1 in docs_extras))

    internal_targets =
      links
      |> Enum.filter(&String.starts_with?(&1, "#"))
      |> Enum.map(&String.trim_leading(&1, "#"))

    heading_ids =
      ~r/^\#{1,6}\s+(.+)$/m
      |> Regex.scan(readme, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&markdown_heading_id/1)

    assert Enum.all?(internal_targets, &(&1 in heading_ids))
    assert docs[:assets] == %{"docs" => "docs"}
    assert "docs" in package_files
    assert File.exists?("docs/assets/paperforge-showcase.png")
  end

  defp markdown_heading_id(heading) do
    heading
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.replace(~r/\s+/u, "-")
    |> String.trim("-")
  end
end
