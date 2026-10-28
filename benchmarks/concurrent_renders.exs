Code.require_file("support/core_probe.exs", __DIR__)
alias PaperForge.BenchProbe
BenchProbe.init()
alias PaperForge.Concurrent
alias PaperForge.Flow
alias PaperForge.Page

workload =
  System.get_env("WORKLOAD", "minimal")
  |> String.to_existing_atom()

unless workload in [:minimal, :small, :medium, :large] do
  raise "WORKLOAD must be minimal, small, medium, or large"
end

default_jobs =
  case workload do
    :small -> 100
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
    :small -> 25
    :minimal -> 0
    :medium -> 500
    :large -> 5_000
  end

preparation_start = System.monotonic_time(:microsecond)

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

preparation_ms = (System.monotonic_time(:microsecond) - preparation_start) / 1000

reference_profile = System.get_env("REFERENCE_PROFILE", "false") == "true"

renderer = fn index ->
  case workload do
    :minimal ->
      PaperForge.new()
      |> PaperForge.add_page(fn page ->
        Page.text(page, "Concurrent benchmark PDF #{index}", x: 72, y: 750)
      end)
      |> PaperForge.to_binary()

    profile when profile in [:small, :medium, :large] ->
      {document, report} =
        PaperForge.new(compress: true)
        |> PaperForge.layout(fn flow ->
          flow =
            if reference_profile do
              flow
              |> Flow.heading("Performance profile")
              |> Flow.paragraph(
                "The same paragraph is intentionally repeated so text metrics can be reused."
              )
              |> Flow.paragraph(
                "The same paragraph is intentionally repeated so text metrics can be reused."
              )
            else
              Flow.heading(flow, "Concurrent #{profile} report #{index}")
            end

          flow
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

expected_pages =
  %{minimal: 1, small: if(reference_profile, do: 2, else: 1), medium: 18, large: 179}[workload]

validate = fn
  %{pdf: pdf, pages: pages} -> BenchProbe.validate!(pdf, pages, expected_pages)
  pdf when is_binary(pdf) -> BenchProbe.validate!(pdf, 1, expected_pages)
end

# Independent parsing of a reference output is outside the timed section.
reference = renderer.(0)
reference_pdf = if is_map(reference), do: reference.pdf, else: reference
{:ok, reference_doc} = PaperForge.PDF.Parser.parse(reference_pdf)
^expected_pages = PaperForge.page_count(reference_doc)
^reference = renderer.(0)
reference_validation = validate.(reference)
if path = System.get_env("REFERENCE_PDF"), do: File.write!(path, reference_pdf)

Enum.each(levels, fn concurrency ->
  warmups = String.to_integer(System.get_env("WARMUPS", "10"))
  Enum.each(1..warmups//1, fn index -> renderer.(index) |> validate.() end)
  :erlang.garbage_collect()
  {gc_before, _, _} = :erlang.statistics(:garbage_collection)
  {reductions_before, _} = :erlang.statistics(:reductions)
  sampler = BenchProbe.start()
  duration_seconds = String.to_integer(System.get_env("DURATION_SECONDS", "0"))
  started_at = System.monotonic_time(:microsecond)
  deadline = started_at + duration_seconds * 1_000_000

  BenchProbe.emit(%{
    event: "measurement_start",
    pid: System.pid(),
    workload: workload,
    concurrency: concurrency,
    schedulers: System.schedulers_online(),
    jobs: jobs,
    preparation_ms: preparation_ms,
    duration_seconds: duration_seconds
  })

  input =
    if duration_seconds > 0 do
      Stream.iterate(1, &(&1 + 1))
      |> Stream.take_while(fn _ -> System.monotonic_time(:microsecond) < deadline end)
    else
      1..jobs
    end

  timed_renderer = fn index ->
    {engine_us, result} = :timer.tc(fn -> renderer.(index) end)
    validation = validate.(result)

    if reference_profile and workload != :minimal and
         validation.sha256 != reference_validation.sha256,
       do: raise("non-deterministic reference output")

    Map.put(validation, :engine_us, engine_us)
  end

  {:ok, supervisor} = Task.Supervisor.start_link()

  initial = %{
    count: 0,
    failures: 0,
    durations: [],
    peak_job_memory: [],
    reductions: 0,
    job_gc: 0,
    first: nil,
    digest: :crypto.hash_init(:sha256),
    interval_count: 0,
    interval_failures: 0,
    interval_start: started_at,
    interval_gc: gc_before
  }

  result =
    Concurrent.stream(supervisor, input, timed_renderer,
      max_concurrency: concurrency,
      timeout: 120_000,
      max_memory_bytes: 1_000_000_000
    )
    |> Enum.reduce(initial, fn r, acc ->
      now = System.monotonic_time(:microsecond)
      ok = r.status == :ok
      failure = if ok, do: 0, else: 1

      if not ok,
        do: BenchProbe.emit(%{event: "job_error", index: r.index, error: inspect(r.error)})

      # Persist raw measurements, never PDF binaries.
      if duration_seconds == 0 do
        BenchProbe.emit(%{
          event: "job",
          index: r.index,
          status: r.status,
          duration_us: r.duration_us,
          engine_us: if(ok, do: r.value.engine_us, else: nil),
          reductions: r.reductions,
          garbage_collections: r.garbage_collections,
          peak_memory_bytes: r.peak_memory_bytes,
          pdf_bytes: if(ok, do: r.value.pdf_bytes, else: nil)
        })
      end

      acc = %{
        acc
        | count: acc.count + 1,
          failures: acc.failures + failure,
          durations: [r.duration_us | if(duration_seconds > 0, do: [], else: acc.durations)],
          peak_job_memory: [
            r.peak_memory_bytes | if(duration_seconds > 0, do: [], else: acc.peak_job_memory)
          ],
          reductions: acc.reductions + r.reductions,
          job_gc: acc.job_gc + r.garbage_collections,
          first: acc.first || if(ok, do: r.value, else: nil),
          digest: if(ok, do: :crypto.hash_update(acc.digest, r.value.sha256), else: acc.digest),
          interval_count: acc.interval_count + 1,
          interval_failures: acc.interval_failures + failure
      }

      if now - acc.interval_start >= 10_000_000 do
        {gc, _, _} = :erlang.statistics(:garbage_collection)

        BenchProbe.emit(%{
          event: "interval",
          elapsed_seconds: (now - started_at) / 1_000_000,
          seconds: (now - acc.interval_start) / 1_000_000,
          completed: acc.interval_count,
          failures: acc.interval_failures,
          pdf_per_second:
            (acc.interval_count - acc.interval_failures) * 1_000_000 / (now - acc.interval_start),
          beam_memory_bytes: :erlang.memory(:total),
          garbage_collections: gc - acc.interval_gc
        })

        %{acc | interval_count: 0, interval_failures: 0, interval_start: now, interval_gc: gc}
      else
        acc
      end
    end)

  elapsed_us = System.monotonic_time(:microsecond) - started_at
  peak_beam_memory = BenchProbe.stop(sampler)
  {gc_after, _, _} = :erlang.statistics(:garbage_collection)
  {reductions_after, _} = :erlang.statistics(:reductions)
  Supervisor.stop(supervisor)
  durations = result.durations
  peak_job_memory = result.peak_job_memory
  stats = BenchProbe.stats(durations)

  report = %{
    event: "concurrency_summary",
    benchmark: :concurrency_scalability,
    workload: workload,
    reference_profile: reference_profile,
    rows_per_document: row_count,
    pages_per_document: result.first && result.first.pages,
    pdf_bytes: result.first && result.first.pdf_bytes,
    jobs: result.count,
    concurrency: concurrency,
    elapsed_ms: Float.round(elapsed_us / 1_000, 2),
    renders_per_second: Float.round((result.count - result.failures) * 1_000_000 / elapsed_us, 4),
    renders_per_minute:
      Float.round((result.count - result.failures) * 60_000_000 / elapsed_us, 2),
    job_median_ms: Float.round(stats.median / 1000, 3),
    job_p95_ms: Float.round(stats.p95 / 1000, 3),
    job_p99_ms: Float.round(stats.p99 / 1000, 3),
    peak_job_memory_median_bytes: percentile.(peak_job_memory, 0.5),
    peak_job_memory_p95_bytes: percentile.(peak_job_memory, 0.95),
    peak_beam_memory_bytes: peak_beam_memory,
    failures: result.failures,
    total_reductions: reductions_after - reductions_before,
    garbage_collections: gc_after - gc_before,
    worker_reductions: result.reductions,
    worker_minor_gc: result.job_gc,
    output_digest: Base.encode16(:crypto.hash_final(result.digest)),
    duration_seconds: duration_seconds,
    warmups: warmups,
    runtime: %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      schedulers_available: System.schedulers(),
      mix_env: Mix.env()
    }
  }

  BenchProbe.emit(report)
  IO.inspect(report, limit: :infinity)
end)

BenchProbe.close()
