alias PaperForge.Declarative

data = %{
  company: "Lumen Atlas",
  period: "FY 2027",
  summary:
    "Lumen Atlas expanded clean urban mobility while improving margin quality, customer retention, and energy efficiency across its operating network.",
  metrics: [
    %{label: "Clean revenue", value: "$562M", change: "+13.2% YoY"},
    %{label: "EBITDA margin", value: "18.4%", change: "+190 bps"},
    %{label: "Cash conversion", value: "87%", change: "+11 points"}
  ],
  program_rows: [
    ["Solar Loop", "North", "$84M", "14.9%", "Density and retention remained ahead of plan."],
    ["Nightline", "Central", "$71M", "13.5%", "Late-hour demand unlocked a high-value commuter segment."],
    ["Harbor Grid", "West", "$66M", "12.8%", "Charging partnerships reduced coastal-route downtime."],
    ["Metro Bloom", "International", "$59M", "12.0%", "The first cross-border program reached break-even."],
    ["Common Route", "North", "$47M", "11.4%", "Employer plans lifted weekday utilization."],
    ["Pulse Pass", "Central", "$39M", "-1.8%", "A measured pricing reset protects long-term retention."]
  ],
  show_outlook: true,
  outlook:
    "Management expects high-single-digit organic growth, gradual margin expansion, and disciplined investment in charging capacity. Scan the code to explore PaperForge and the source template behind this report."
}

template_path = Path.join(__DIR__, "declarative_annual_report.paperforge")
output_path = Path.expand("../tmp/paper_forge_1_2_declarative_report.pdf", __DIR__)

with {:ok, template} <- Declarative.load(template_path),
     {:ok, document, report} <- Declarative.render(template, data),
     :ok <- File.mkdir_p(Path.dirname(output_path)),
     :ok <- PaperForge.write(document, output_path) do
  IO.puts("Generated #{output_path} (#{report.pages} pages)")
else
  {:error, errors} when is_list(errors) ->
    Enum.each(errors, &IO.puts("#{&1.path}: #{&1.message}"))
    System.halt(1)

  {:error, reason} ->
    IO.puts("Could not write report: #{inspect(reason)}")
    System.halt(1)
end
