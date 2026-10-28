alias PaperForge.{Concurrent, Flow}

render = fn i ->
  data = "b874a89e-8397-4fb1-9411-#{String.pad_leading(Integer.to_string(i), 12, "0")}"

  {doc, _} =
    PaperForge.new()
    |> PaperForge.layout(
      fn flow ->
        flow
        |> Flow.heading("Invitation", size: 20)
        |> Flow.paragraph("Guest #{i}", size: 11)
        |> Flow.qr_code(data, width: 96, height: 96)
      end,
      page_options: [size: {300, 420}, margins: 30]
    )

  PaperForge.to_binary(doc)
end

for i <- 1..10, do: render.(i)

samples =
  for i <- 1..100 do
    {us, pdf} = :timer.tc(fn -> render.(i) end)
    %{us: us, bytes: byte_size(pdf)}
  end

runs =
  for c <- [1, 4, 10], repeat <- 1..3 do
    {us, results} =
      :timer.tc(fn ->
        Concurrent.run(1..500, fn i -> byte_size(render.(i)) end,
          max_concurrency: c,
          timeout: 120_000
        )
      end)

    %{
      concurrency: c,
      repeat: repeat,
      pdf_per_second: 500_000_000 / us,
      failures: Enum.count(results, &(&1.status != :ok))
    }
  end

report = %{
  samples: samples,
  runs: runs,
  median_us: Enum.at(Enum.sort(Enum.map(samples, & &1.us)), 49),
  runtime: %{
    elixir: System.version(),
    otp: System.otp_release(),
    schedulers: System.schedulers_online(),
    env: Mix.env()
  }
}

output = System.fetch_env!("QR_BENCH_OUTPUT")
File.write!(output, Jason.encode!(report, pretty: true), [:exclusive])
File.write!(output <> ".pdf", render.(1))
IO.inspect(Map.drop(report, [:samples]))
