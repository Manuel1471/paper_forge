defmodule PaperForge.Examples.AtlasReport do
  @moduledoc """
  Reproducible editorial and pagination workload. All companies and figures are fictional.
  Design is loaded from atlas_2026.paperforge; this module only supplies data and attachments.
  Uses built-in fonts and vector artwork; no network or system font dependencies.
  """
  def routes do
    cities = [
      "Monterrey",
      "Saltillo",
      "Querétaro",
      "León",
      "Puebla",
      "Mérida",
      "Toluca",
      "Guadalajara"
    ]

    for n <- 1..120 do
      %{
        id: "AT-#{String.pad_leading(to_string(n), 3, "0")}",
        origin: Enum.at(cities, rem(n - 1, 8)),
        destination: Enum.at(cities, rem(n + 2, 8)),
        trips: 180 + rem(n * 17, 220),
        on_time: 94.0 + rem(n * 13, 50) / 10,
        km: 240 + rem(n * 37, 920)
      }
    end
  end

  def months do
    Enum.zip(
      ~w(Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic),
      [72, 74, 79, 81, 86, 89, 91, 94, 98, 102, 109, 115]
    )
  end

  def build do
    {:ok, source} = PaperForge.Declarative.load(Path.expand("../atlas_2026.paperforge", __DIR__))

    rows =
      Enum.map(routes(), fn row ->
        [
          row.id,
          "#{row.origin}\n#{row.destination}",
          Integer.to_string(row.trips),
          "#{row.on_time}%",
          "#{row.km} km"
        ]
      end)

    {:ok, document, report} = PaperForge.Declarative.render(source, %{"route_rows" => rows})

    document =
      PaperForge.attach(document, "atlas-routes.json", Jason.encode!(routes(), pretty: true),
        mime_type: "application/json"
      )

    {document, report}
  end
end
