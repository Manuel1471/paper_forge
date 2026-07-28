defmodule PaperForge.MixProject do
  use Mix.Project

  @version "0.5.0"
  @source_url "https://github.com/Manuel1471/paper_forge"

  def project do
    [
      app: :paper_forge,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "PaperForge",
      source_url: "https://github.com/Manuel1471/paper_forge",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    A pure Elixir PDF generation engine with unified document layout, vector
    graphics, embedded TrueType fonts, Unicode text, JPEG and PNG images,
    navigation, compression, metadata, and multi-page PDF output.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/Manuel1471/paper_forge",
        "Changelog" => "https://github.com/Manuel1471/paper_forge/blob/main/CHANGELOG.md"
      },
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "PaperForge",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ]
    ]
  end
end
