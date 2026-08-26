defmodule PaperForge.Runtime.CircuitBreaker do
  @moduledoc false

  use GenServer

  alias PaperForge.Error

  @name __MODULE__
  @default_failure_threshold 3
  @default_reset_after_ms 5_000
  @default_max_entries 1_024

  @spec protect(term(), (-> {:ok, term()} | {:error, term()}), keyword()) ::
          {:ok, term()} | {:error, term() | Error.t()}
  def protect(key, function, options \\ []) when is_function(function, 0) do
    ensure_started()

    case GenServer.call(@name, {:allow, key, options}) do
      :ok ->
        result = function.()

        outcome =
          if trip?(result, Keyword.get(options, :trip_on, :all)),
            do: result,
            else: {:ok, :healthy}

        GenServer.call(@name, {:record, key, outcome, options})

        result

      {:open, retry_after_ms} ->
        {:error, Error.circuit_open(key, retry_after_ms)}
    end
  end

  @spec reset() :: :ok
  def reset do
    ensure_started()
    GenServer.call(@name, :reset)
  end

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call(:reset, _from, _state), do: {:reply, :ok, %{}}

  def handle_call({:allow, key, options}, _from, state) do
    now = System.monotonic_time(:millisecond)
    state = prune_state(state, now, max_entries(options))

    case Map.get(state, key) do
      %{failures: failures, opened_until: opened_until}
      when failures > 0 and opened_until != 0 and opened_until > now ->
        {:reply, {:open, opened_until - now}, state}

      %{opened_until: opened_until} when opened_until != 0 ->
        {:reply, :ok, Map.delete(state, key)}

      _ ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:record, key, {:ok, _value}, _options}, _from, state) do
    {:reply, :ok, Map.delete(state, key)}
  end

  def handle_call({:record, key, {:error, _reason}, options}, _from, state) do
    threshold = Keyword.get(options, :failure_threshold, @default_failure_threshold)
    reset_after_ms = Keyword.get(options, :reset_after_ms, @default_reset_after_ms)
    now = System.monotonic_time(:millisecond)

    entry = Map.get(state, key, %{failures: 0, opened_until: 0})
    failures = entry.failures + 1

    updated = %{
      failures: failures,
      opened_until:
        if(failures >= threshold,
          do: now + reset_after_ms,
          else: 0
        ),
      expires_at: now + reset_after_ms,
      updated_at: now
    }

    state =
      state
      |> prune_state(now, max_entries(options))
      |> put_bounded(key, updated, max_entries(options))

    {:reply, :ok, state}
  end

  defp trip?({:error, %PaperForge.Error{}}, :runtime), do: true
  defp trip?({:error, _reason}, :runtime), do: false
  defp trip?({:error, _reason}, :all), do: true
  defp trip?(_result, _mode), do: false

  defp max_entries(options) do
    case Keyword.get(options, :max_entries, @default_max_entries) do
      value when is_integer(value) and value > 0 ->
        value

      value ->
        raise ArgumentError, "max_entries must be a positive integer, got: #{inspect(value)}"
    end
  end

  defp prune_state(state, now, maximum) do
    state
    |> Enum.reject(fn {_key, entry} -> Map.get(entry, :expires_at, now + 1) <= now end)
    |> Map.new()
    |> trim_to(maximum)
  end

  defp put_bounded(state, key, entry, maximum) do
    state
    |> Map.put(key, entry)
    |> trim_to(maximum)
  end

  defp trim_to(state, maximum) when map_size(state) <= maximum, do: state

  defp trim_to(state, maximum) do
    state
    |> Enum.sort_by(fn {_key, entry} -> Map.get(entry, :updated_at, 0) end, :desc)
    |> Enum.take(maximum)
    |> Map.new()
  end

  defp ensure_started do
    case Process.whereis(@name) do
      nil ->
        case GenServer.start(__MODULE__, %{}, name: @name) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end
end
