alias PaperForge.{Concurrent, Flow}

renderers = [
  small: fn id ->
    {doc, _} =
      PaperForge.new()
      |> PaperForge.layout(fn flow ->
        flow
        |> Flow.heading("Report #{id}")
        |> Flow.paragraph("Measured production rendering with bounded concurrency.")
      end)

    PaperForge.to_binary(doc)
  end,
  qr: fn id ->
    {doc, _} =
      PaperForge.new()
      |> PaperForge.layout(fn flow ->
        flow
        |> Flow.heading("Invitation #{id}")
        |> Flow.qr_code("invite:#{id}:b874a89e-8397-4fb1-9411", size: 96)
      end)

    PaperForge.to_binary(doc)
  end,
  visual: fn id ->
    children =
      Flow.new()
      |> Flow.paragraph("Identity #{id}", size: 20)
      |> Flow.paragraph("A reusable measured card with its own code.")
      |> Flow.qr_code("visual:#{id}:b874a89e", size: 72)

    {doc, _} =
      PaperForge.new()
      |> PaperForge.layout(fn flow ->
        Flow.visual(flow, :box, children,
          padding: 18,
          border_radius: 12,
          background_color: PaperForge.Color.gray(0.95)
        )
      end)

    PaperForge.to_binary(doc)
  end
]

heap = System.get_env("WORKER_HEAP")
opts = if heap, do: [worker_heap_size: String.to_integer(heap)], else: []

results =
  for {name, renderer} <- renderers, c <- [1, 4, 10], repeat <- 1..3 do
    Concurrent.run(1..20, renderer, [max_concurrency: c] ++ opts)

    {us, results} =
      :timer.tc(fn -> Concurrent.run(1..300, renderer, [max_concurrency: c] ++ opts) end)

    %{
      scenario: name,
      concurrency: c,
      repeat: repeat,
      pdf_per_second: 300_000_000 / us,
      failures: Enum.count(results, &(&1.status != :ok)),
      max_job_memory: Enum.max(Enum.map(results, & &1.peak_memory_bytes)),
      reductions: Enum.sum(Enum.map(results, & &1.reductions)),
      minor_gcs: Enum.sum(Enum.map(results, & &1.garbage_collections))
    }
  end

path = System.fetch_env!("TUNING_OUTPUT")

File.write!(
  path,
  Jason.encode!(
    %{
      runtime: %{
        elixir: System.version(),
        otp: System.otp_release(),
        schedulers: System.schedulers_online()
      },
      worker_heap: heap,
      results: results
    },
    pretty: true
  ),
  [:exclusive]
)

IO.puts(path)
