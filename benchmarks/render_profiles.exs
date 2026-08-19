alias PaperForge.Flow

cache_module = PaperForge.PerformanceCache

reset_cache = fn ->
  if Code.ensure_loaded?(cache_module) and function_exported?(cache_module, :reset, 0) do
    apply(cache_module, :reset, [])
  else
    :ok
  end
end

cache_stats = fn ->
  if Code.ensure_loaded?(cache_module) and function_exported?(cache_module, :stats, 0) do
    apply(cache_module, :stats, [])
  else
    %{}
  end
end

sample_count = String.to_integer(System.get_env("SAMPLES", "10"))
warmup_count = String.to_integer(System.get_env("WARMUPS", "2"))
selected_profile = System.get_env("PROFILE", "all")

unless sample_count > 0 do
  raise "SAMPLES must be greater than zero"
end

unless warmup_count >= 0 do
  raise "WARMUPS must be zero or greater"
end

profiles =
  [
    small: 25,
    medium: 500,
    large: 5_000
  ]
  |> Enum.filter(fn {name, _rows} ->
    selected_profile == "all" or selected_profile == Atom.to_string(name)
  end)

percentile = fn values, percentile ->
  sorted = Enum.sort(values)
  index = max(ceil(length(sorted) * percentile) - 1, 0)
  Enum.at(sorted, index)
end

summarize = fn values ->
  sorted = Enum.sort(values)
  count = length(sorted)

  median =
    if rem(count, 2) == 0 do
      (Enum.at(sorted, div(count, 2) - 1) + Enum.at(sorted, div(count, 2))) / 2
    else
      Enum.at(sorted, div(count, 2))
    end

  %{
    median: Float.round(median * 1.0, 2),
    p95: Float.round(percentile.(sorted, 0.95) * 1.0, 2),
    min: Float.round(hd(sorted) * 1.0, 2),
    max: Float.round(List.last(sorted) * 1.0, 2)
  }
end

sample = fn row_count ->
  rows =
    for index <- 1..row_count do
      [
        "ROW-#{index}",
        "Region #{rem(index, 8) + 1}",
        "$#{index * 17}",
        "#{rem(index * 7, 100)}%"
      ]
    end

  parent = self()

  worker =
    spawn(fn ->
      receive do
        :run ->
          reset_cache.()
          :erlang.garbage_collect()

          {:reductions, reductions_before} = Process.info(self(), :reductions)
          {gc_count_before, gc_words_before, _} = :erlang.statistics(:garbage_collection)

          {layout_us, {document, report}} =
            :timer.tc(fn ->
              PaperForge.new(compress: true)
              |> PaperForge.layout(fn flow ->
                flow
                |> Flow.heading("Performance profile")
                |> Flow.paragraph(
                  "The same paragraph is intentionally repeated so text metrics can be reused."
                )
                |> Flow.paragraph(
                  "The same paragraph is intentionally repeated so text metrics can be reused."
                )
                |> Flow.table(
                  ["Identifier", "Region", "Revenue", "Growth"],
                  rows,
                  repeat_header: true,
                  row_split: :split,
                  column_widths: [120, 120, 100, 80]
                )
              end)
            end)

          {cold_us, first_pdf} = :timer.tc(fn -> PaperForge.to_binary(document) end)
          {warm_us, second_pdf} = :timer.tc(fn -> PaperForge.to_binary(document) end)
          {gc_count_after, gc_words_after, _} = :erlang.statistics(:garbage_collection)
          {:reductions, reductions_after} = Process.info(self(), :reductions)

          unless first_pdf == second_pdf, do: raise("non-deterministic PDF output")

          send(parent, {
            :sample,
            self(),
            %{
              layout_ms: layout_us / 1_000,
              cold_serialize_ms: cold_us / 1_000,
              warm_serialize_ms: warm_us / 1_000,
              total_ms: (layout_us + cold_us + warm_us) / 1_000,
              reductions: reductions_after - reductions_before,
              garbage_collections: gc_count_after - gc_count_before,
              reclaimed_words: gc_words_after - gc_words_before,
              pages: report.pages,
              pdf_bytes: byte_size(first_pdf),
              cache: cache_stats.()
            }
          })

          receive do
            :release -> :ok
          end
      end
    end)

  sampler =
    spawn(fn ->
      initial_memory =
        case Process.info(worker, :memory) do
          {:memory, bytes} -> bytes
          nil -> 0
        end

      poll = fn poll, peak ->
        receive do
          {:stop, caller} ->
            send(caller, {:peak_memory, peak})
        after
          1 ->
            current =
              case Process.info(worker, :memory) do
                {:memory, bytes} -> bytes
                nil -> 0
              end

            poll.(poll, max(peak, current))
        end
      end

      poll.(poll, initial_memory)
    end)

  send(worker, :run)

  result =
    receive do
      {:sample, ^worker, result} -> result
    after
      120_000 -> raise "benchmark sample timed out"
    end

  send(sampler, {:stop, self()})

  peak_memory =
    receive do
      {:peak_memory, bytes} -> bytes
    after
      5_000 -> raise "memory sampler timed out"
    end

  send(worker, :release)
  Map.put(result, :peak_process_memory_bytes, peak_memory)
end

Enum.each(profiles, fn {name, rows} ->
  Enum.each(List.duplicate(:warmup, warmup_count), fn _ -> sample.(rows) end)
  samples = Enum.map(1..sample_count, fn _ -> sample.(rows) end)

  first = hd(samples)

  report = %{
    profile: name,
    rows: rows,
    samples: sample_count,
    warmups: warmup_count,
    pages: first.pages,
    pdf_bytes: first.pdf_bytes,
    layout_ms: summarize.(Enum.map(samples, & &1.layout_ms)),
    cold_serialize_ms: summarize.(Enum.map(samples, & &1.cold_serialize_ms)),
    warm_serialize_ms: summarize.(Enum.map(samples, & &1.warm_serialize_ms)),
    total_ms: summarize.(Enum.map(samples, & &1.total_ms)),
    peak_process_memory_bytes: summarize.(Enum.map(samples, & &1.peak_process_memory_bytes)),
    reductions: summarize.(Enum.map(samples, & &1.reductions)),
    garbage_collections: summarize.(Enum.map(samples, & &1.garbage_collections)),
    reclaimed_words: summarize.(Enum.map(samples, & &1.reclaimed_words)),
    cache: first.cache,
    runtime: %{
      elixir: System.version(),
      otp: System.otp_release(),
      schedulers: System.schedulers_online(),
      mix_env: Mix.env()
    }
  }

  IO.inspect(report, pretty: true, limit: :infinity)
end)
