defmodule PaperForge.BenchProbe do
  def init do
    if path = System.get_env("RESULT_JSONL") do
      {:ok, io} = File.open(path, [:append, {:delayed_write, 65536, 100}])
      :persistent_term.put({__MODULE__, :io}, io)
    end
  end

  def close do
    if io = :persistent_term.get({__MODULE__, :io}, nil), do: File.close(io)
  end

  def emit(event) do
    if io = :persistent_term.get({__MODULE__, :io}, nil) do
      IO.binwrite(io, Jason.encode!(event) <> "\n")
    end
  end

  def stats(values) do
    sorted = Enum.sort(values)
    n = length(sorted)
    p = fn fraction -> Enum.at(sorted, max(ceil(n * fraction) - 1, 0)) end

    %{
      mean: Enum.sum(sorted) / n,
      median: p.(0.5),
      p95: p.(0.95),
      p99: p.(0.99),
      min: hd(sorted),
      max: List.last(sorted)
    }
  end

  def start do
    owner = self()
    spawn_link(fn -> poll(owner, :erlang.memory(:total)) end)
  end

  defp poll(owner, peak) do
    receive do
      :stop -> send(owner, {:beam_peak, peak})
    after
      200 ->
        memory = :erlang.memory(:total)

        emit(%{
          event: "beam_sample",
          monotonic_ms: System.monotonic_time(:millisecond),
          memory_bytes: memory
        })

        poll(owner, max(memory, peak))
    end
  end

  def stop(pid) do
    send(pid, :stop)

    receive do
      {:beam_peak, peak} -> peak
    after
      5000 -> raise "sampler timeout"
    end
  end

  def validate!(pdf, pages, expected) do
    unless pages == expected and String.starts_with?(pdf, "%PDF-") and
             String.ends_with?(String.trim_trailing(pdf), "%%EOF"),
           do: raise("invalid PDF envelope or page count: #{pages}, expected #{expected}")

    %{pages: pages, pdf_bytes: byte_size(pdf), sha256: Base.encode16(:crypto.hash(:sha256, pdf))}
  end
end
