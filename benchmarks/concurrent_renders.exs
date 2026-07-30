alias PaperForge.Concurrent
alias PaperForge.Flow
alias PaperForge.Page

workload =
  System.get_env("WORKLOAD", "minimal")
  |> String.to_existing_atom()

unless workload in [:minimal, :medium, :large] do
  raise "WORKLOAD must be minimal, medium, or large"
end

default_jobs =
  case workload do
    :minimal -> 1_000
    :medium -> 100
    :large -> 20
  end

jobs = String.to_integer(System.get_env("JOBS", Integer.to_string(default_jobs)))

levels =
  System.get_env(
    "CONCURRENCY",
    "1,#{System.schedulers_online()},#{System.schedulers_online() * 2}"
  )
  |> String.split(",", trim: true)
  |> Enum.map(&String.to_integer/1)
  |> Enum.uniq()

percentile = fn values, percentile ->
  sorted = Enum.sort(values)
  Enum.at(sorted, max(ceil(length(sorted) * percentile) - 1, 0))
end

row_count =
  case workload do
    :minimal -> 0
    :medium -> 500
    :large -> 5_000
  end

rows =
  if row_count == 0 do
    []
  else
    for index <- 1..row_count do
      [
        "ROW-#{index}",
        "Region #{rem(index, 8) + 1}",
        "$#{index * 17}",
        "#{rem(index * 7, 100)}%"
      ]
    end
  end

renderer = fn index ->
  case workload do
    :minimal ->
      PaperForge.new()
      |> PaperForge.add_page(fn page ->
        Page.text(page, "Concurrent benchmark PDF #{index}", x: 72, y: 750)
      end)
      |> PaperForge.to_binary()

    profile when profile in [:medium, :large] ->
      {document, report} =
        PaperForge.new(compress: true)
        |> PaperForge.layout(fn flow ->
          flow
          |> Flow.heading("Concurrent #{profile} report #{index}")
          |> Flow.table(
            ["Identifier", "Region", "Revenue", "Growth"],
            rows,
            repeat_header: true,
            row_split: :split,
            column_widths: [120, 120, 100, 80]
          )
        end)

      %{pdf: PaperForge.to_binary(document), pages: report.pages}
  end
end

Enum.each(levels, fn concurrency ->
  :erlang.garbage_collect()
  parent = self()

  sampler =
    spawn(fn ->
      poll = fn poll, peak ->
        receive do
          {:stop, caller} -> send(caller, {:peak_beam_memory, peak})
        after
          2 -> poll.(poll, max(peak, :erlang.memory(:total)))
        end
      end

      poll.(poll, :erlang.memory(:total))
    end)

  started_at = System.monotonic_time()

  results =
    Concurrent.run(
      1..jobs,
      renderer,
      max_concurrency: concurrency,
      timeout: 120_000
    )

  elapsed_us =
    System.convert_time_unit(System.monotonic_time() - started_at, :native, :microsecond)

  send(sampler, {:stop, parent})

  peak_beam_memory =
    receive do
      {:peak_beam_memory, bytes} -> bytes
    end

  durations = Enum.map(results, & &1.duration_us)
  peak_job_memory = Enum.map(results, & &1.peak_memory_bytes)
  failures = Enum.count(results, &(&1.status != :ok))

  {pages, pdf_bytes} =
    case Enum.find(results, &(&1.status == :ok)) do
      %{value: %{pdf: pdf, pages: pages}} -> {pages, byte_size(pdf)}
      %{value: pdf} when is_binary(pdf) -> {1, byte_size(pdf)}
      nil -> {nil, nil}
    end

  IO.inspect(%{
    benchmark: :concurrency_scalability,
    workload: workload,
    rows_per_document: row_count,
    pages_per_document: pages,
    pdf_bytes: pdf_bytes,
    jobs: jobs,
    concurrency: concurrency,
    elapsed_ms: Float.round(elapsed_us / 1_000, 2),
    renders_per_second: Float.round(jobs * 1_000_000 / elapsed_us, 2),
    job_median_ms: Float.round(percentile.(durations, 0.5) / 1_000, 2),
    job_p95_ms: Float.round(percentile.(durations, 0.95) / 1_000, 2),
    peak_job_memory_median_bytes: percentile.(peak_job_memory, 0.5),
    peak_job_memory_p95_bytes: percentile.(peak_job_memory, 0.95),
    peak_beam_memory_bytes: peak_beam_memory,
    failures: failures,
    total_reductions: Enum.sum(Enum.map(results, & &1.reductions)),
    garbage_collections: Enum.sum(Enum.map(results, & &1.garbage_collections)),
    runtime: %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      mix_env: Mix.env()
    }
  })
end)
