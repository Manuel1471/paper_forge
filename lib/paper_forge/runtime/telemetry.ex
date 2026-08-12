defmodule PaperForge.Telemetry do
  @moduledoc """
  Telemetry event contract and instrumentation helpers.

  PaperForge emits:

  - `[:paperforge, :render, :start]`
  - `[:paperforge, :render, :stop]`
  - `[:paperforge, :render, :exception]`
  - `[:paperforge, :batch, :job]`
  - `[:paperforge, :batch, :complete]`
  """

  alias PaperForge.Document

  @render_start [:paperforge, :render, :start]
  @render_stop [:paperforge, :render, :stop]
  @render_exception [:paperforge, :render, :exception]
  @batch_job [:paperforge, :batch, :job]
  @batch_complete [:paperforge, :batch, :complete]

  @spec render(Document.t(), term(), (-> term())) :: term()
  def render(%Document{} = document, output, function)
      when is_function(function, 0) do
    metadata = %{pages: page_count(document), output: output, status: :started}
    started_at = System.monotonic_time()
    before = process_metrics()

    :telemetry.execute(
      @render_start,
      %{system_time: System.system_time()},
      metadata
    )

    try do
      value = function.()
      measurements = measurements(started_at, before, output_bytes(value, output))

      :telemetry.execute(
        @render_stop,
        measurements,
        %{metadata | status: result_status(value)}
      )

      value
    rescue
      exception ->
        emit_exception(metadata, started_at, before, :error, exception, __STACKTRACE__)
        reraise exception, __STACKTRACE__
    catch
      kind, reason ->
        emit_exception(metadata, started_at, before, kind, reason, __STACKTRACE__)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @spec batch_job(map()) :: :ok
  def batch_job(%{duration_us: duration_us} = metadata) do
    value = Map.get(metadata, :value)

    measurements = %{
      duration: System.convert_time_unit(duration_us, :microsecond, :native),
      memory: Map.get(metadata, :peak_memory_bytes, 0),
      reductions: Map.get(metadata, :reductions, 0),
      gc: Map.get(metadata, :garbage_collections, 0),
      bytes: result_bytes(value)
    }

    metadata =
      metadata
      |> Map.drop([:value])
      |> Map.put(:attempt, Map.get(metadata, :attempts, 1))
      |> Map.delete(:attempts)
      |> Map.put(:pages, result_pages(value))

    :telemetry.execute(@batch_job, measurements, metadata)
  end

  @spec batch_complete(map(), map()) :: :ok
  def batch_complete(measurements, metadata) when is_map(measurements) and is_map(metadata) do
    :telemetry.execute(@batch_complete, measurements, metadata)
  end

  @spec events() :: [[atom()]]
  def events do
    [@render_start, @render_stop, @render_exception, @batch_job, @batch_complete]
  end

  defp emit_exception(metadata, started_at, before, kind, reason, stacktrace) do
    :telemetry.execute(
      @render_exception,
      measurements(started_at, before, 0),
      Map.merge(metadata, %{
        status: :error,
        kind: kind,
        reason: reason,
        stacktrace: stacktrace
      })
    )
  end

  defp measurements(started_at, before, bytes) do
    current = process_metrics()

    %{
      duration: System.monotonic_time() - started_at,
      memory: current.memory,
      memory_delta: current.memory - before.memory,
      reductions: current.reductions - before.reductions,
      gc: max(current.gc - before.gc, 0),
      bytes: bytes
    }
  end

  defp process_metrics do
    {:memory, memory} = Process.info(self(), :memory)
    {:reductions, reductions} = Process.info(self(), :reductions)
    {:garbage_collection, gc} = Process.info(self(), :garbage_collection)

    %{
      memory: memory,
      reductions: reductions,
      gc: Keyword.fetch!(gc, :minor_gcs)
    }
  end

  defp page_count(document) do
    document
    |> Document.fetch_object!(document.pages_reference)
    |> Map.fetch!(:value)
    |> Map.fetch!("Count")
  end

  defp output_bytes(value, :binary) when is_binary(value), do: byte_size(value)

  defp output_bytes(:ok, {:file, path}) do
    case File.stat(path) do
      {:ok, stat} -> stat.size
      {:error, _reason} -> 0
    end
  end

  defp output_bytes(_value, _output), do: 0

  defp result_status({:error, _reason}), do: :error
  defp result_status(_value), do: :ok

  defp result_bytes(value) when is_binary(value), do: byte_size(value)
  defp result_bytes(%{pdf: pdf}) when is_binary(pdf), do: byte_size(pdf)
  defp result_bytes(_value), do: 0

  defp result_pages(%{pages: pages}) when is_integer(pages), do: pages
  defp result_pages(_value), do: nil
end
