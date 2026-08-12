defmodule PaperForge.MixProject do
  use Mix.Project

  @version "1.4.2"
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
      extra_applications: [:logger, :crypto, :public_key, :xmerl]
    ]
  end

  defp deps do
    [
      {:qiroex, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:earmark_parser, "~> 1.4"},
      {:telemetry, "~> 1.3"},
      {:sign_core, "~> 0.1.4"},
      {:soft_signer, "~> 0.1.0"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Document engineering for the BEAM. Build, secure, validate, and transform
    native PDF documents entirely in Elixir, with declarative templates,
    measured layout, interoperability, accessibility, and production rendering.
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
        "priv",
        "docs",
        "examples",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "CODE_OF_CONDUCT.md",
        "API.md",
        "ARCHITECTURE.md",
        "DECLARATIVE.md",
        "PAPERFORGE_TEMPLATES.md",
        "PHOENIX.md",
        "INTEROPERABILITY.md",
        "SCIENTIFIC.md",
        "MIGRATING.md",
        "PRODUCTION.md",
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
      assets: %{"docs" => "docs"},
      extras: [
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "CODE_OF_CONDUCT.md",
        "API.md",
        "ARCHITECTURE.md",
        "DECLARATIVE.md",
        "PAPERFORGE_TEMPLATES.md",
        "PHOENIX.md",
        "INTEROPERABILITY.md",
        "SCIENTIFIC.md",
        "MIGRATING.md",
        "PRODUCTION.md",
        "LICENSE"
      ]
    ]
  end
end
