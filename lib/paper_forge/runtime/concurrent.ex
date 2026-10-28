defmodule PaperForge.Concurrent do
  @moduledoc """
  Concurrent, backpressured execution for independent PDF render jobs.

  Phoenix applications should place a `Task.Supervisor` in their supervision
  tree and pass its name to `stream/4` or through the `:supervisor` option of
  `run/3`.
  """

  alias PaperForge.Error
  alias PaperForge.Telemetry

  defmodule Result do
    @moduledoc """
    Outcome and runtime metrics for one concurrent render job.
    """

    @enforce_keys [
      :id,
      :index,
      :status,
      :duration_us,
      :reductions,
      :garbage_collections,
      :attempts,
      :peak_memory_bytes
    ]
    defstruct [
      :id,
      :index,
      :status,
      :value,
      :error,
      :duration_us,
      :reductions,
      :garbage_collections,
      :attempts,
      :peak_memory_bytes
    ]

    @type status :: :ok | :error | :timeout | :resource_limit | :cancelled

    @type t :: %__MODULE__{
            id: term(),
            index: non_neg_integer(),
            status: status(),
            value: term() | nil,
            error: term() | nil,
            duration_us: non_neg_integer(),
            reductions: non_neg_integer(),
            garbage_collections: non_neg_integer(),
            attempts: pos_integer(),
            peak_memory_bytes: non_neg_integer()
          }
  end

  @type option ::
          {:supervisor, Supervisor.supervisor()}
          | {:max_concurrency, pos_integer()}
          | {:timeout, timeout()}
          | {:ordered, boolean()}
          | {:job_id, (term(), non_neg_integer() -> term())}
          | {:on_result, (Result.t() -> term())}
          | {:max_attempts, pos_integer()}
          | {:retry_delay, non_neg_integer()}
          | {:retry_on, [Result.status()]}
          | {:max_memory_bytes, pos_integer() | :infinity}
          | {:max_reductions, pos_integer() | :infinity}
          | {:worker_heap_size, pos_integer()}

  @doc """
  Executes all jobs and returns their isolated results.

  When no supervisor is supplied, PaperForge starts and stops a private
  `Task.Supervisor` for the duration of the call.
  """
  @spec run(Enumerable.t(), (term() -> term()), [option()]) :: [Result.t()]
  def run(jobs, renderer, options \\ [])
      when is_function(renderer, 1) and is_list(options) do
    started_at = System.monotonic_time()

    results =
      case Keyword.get(options, :supervisor) do
        nil ->
          {:ok, supervisor} = Task.Supervisor.start_link()

          try do
            supervisor
            |> stream(jobs, renderer, options)
            |> Enum.to_list()
          after
            Supervisor.stop(supervisor)
          end

        supervisor ->
          supervisor
          |> stream(jobs, renderer, options)
          |> Enum.to_list()
      end

    emit_batch_complete(results, started_at, options)
    results
  end

  @doc """
  Returns a lazy, backpressured stream of render results.

  The supplied supervisor should normally be owned by the calling
  application's supervision tree.
  """
  @spec stream(
          Supervisor.supervisor(),
          Enumerable.t(),
          (term() -> term()),
          [option()]
        ) :: Enumerable.t()
  def stream(supervisor, jobs, renderer, options \\ [])
      when is_function(renderer, 1) and is_list(options) do
    max_concurrency = Keyword.get(options, :max_concurrency, System.schedulers_online())
    timeout = Keyword.get(options, :timeout, 30_000)
    ordered = Keyword.get(options, :ordered, true)
    job_id = Keyword.get(options, :job_id, fn _job, index -> index end)
    on_result = Keyword.get(options, :on_result, fn _result -> :ok end)
    execution_options = execution_options(options, timeout)

    validate_options!(max_concurrency, timeout, job_id, on_result, execution_options)

    stream = Stream.with_index(jobs)

    Task.Supervisor.async_stream_nolink(
      supervisor,
      stream,
      fn {job, index} ->
        result =
          execute(job, index, job_id.(job, index), renderer, execution_options)

        on_result.(result)
        result
      end,
      max_concurrency: max_concurrency,
      ordered: ordered,
      timeout: :infinity
    )
    |> Stream.map(fn
      {:ok, %Result{} = result} ->
        result

      {:exit, reason} ->
        %Result{
          id: nil,
          index: 0,
          status: :error,
          error: %{kind: :task_exit, reason: reason, code: "PF8105"},
          duration_us: 0,
          reductions: 0,
          garbage_collections: 0,
          attempts: 1,
          peak_memory_bytes: 0
        }
    end)
  end

  @doc """
  Starts one supervised job and returns its task handle.
  """
  @spec start_job(
          Supervisor.supervisor(),
          term(),
          (term() -> term()),
          keyword()
        ) :: Task.t()
  def start_job(supervisor, job, renderer, options \\ [])
      when is_function(renderer, 1) and is_list(options) do
    timeout = Keyword.get(options, :timeout, 30_000)
    id = Keyword.get(options, :id, 0)
    execution_options = execution_options(options, timeout)
    validate_options!(1, timeout, fn _, _ -> id end, fn _ -> :ok end, execution_options)

    Task.Supervisor.async_nolink(supervisor, fn ->
      execute(job, 0, id, renderer, execution_options)
    end)
  end

  @doc """
  Cancels a task, allowing a graceful shutdown before forcing termination.
  """
  @spec cancel(Task.t(), timeout()) :: {:ok, term()} | {:exit, term()} | nil
  def cancel(%Task{} = task, shutdown_timeout \\ 5_000) do
    case Task.shutdown(task, shutdown_timeout) do
      nil ->
        if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill), else: nil

      result ->
        result
    end
  end

  defp execute(job, index, id, renderer, options) do
    execute_attempt(job, index, id, renderer, options, 1)
  end

  defp execute_attempt(job, index, id, renderer, options, attempt) do
    result = execute_once(job, index, id, renderer, options.timeout, attempt, options)
    Telemetry.batch_job(Map.from_struct(result))

    if result.status in options.retry_on and attempt < options.max_attempts do
      if options.retry_delay > 0, do: Process.sleep(options.retry_delay)
      execute_attempt(job, index, id, renderer, options, attempt + 1)
    else
      result
    end
  end

  defp execute_once(job, index, id, renderer, timeout, attempt, limits) do
    parent = self()
    token = make_ref()
    started_at = System.monotonic_time()

    {pid, monitor} =
      :erlang.spawn_opt(
        fn ->
          if limits.worker_heap_size == 233, do: :erlang.garbage_collect()
          {:reductions, reductions_before} = Process.info(self(), :reductions)
          {:garbage_collection, gc_before} = Process.info(self(), :garbage_collection)

          outcome =
            try do
              {:ok, renderer.(job)}
            rescue
              exception ->
                {:error,
                 %{
                   kind: :exception,
                   code: "PF8105",
                   exception: exception,
                   stacktrace: __STACKTRACE__
                 }}
            catch
              kind, reason ->
                {:error,
                 %{kind: kind, code: "PF8105", reason: reason, stacktrace: __STACKTRACE__}}
            end

          {:garbage_collection, gc_after} = Process.info(self(), :garbage_collection)
          {:reductions, reductions_after} = Process.info(self(), :reductions)

          send(
            parent,
            {token, outcome, reductions_after - reductions_before,
             max(0, Keyword.fetch!(gc_after, :minor_gcs) - Keyword.fetch!(gc_before, :minor_gcs)),
             process_memory(self())}
          )
        end,
        [:link, :monitor, {:min_heap_size, limits.worker_heap_size}]
      )

    receive_result(
      token,
      pid,
      monitor,
      id,
      index,
      started_at,
      timeout,
      attempt,
      limits,
      0
    )
  end

  defp receive_result(
         token,
         pid,
         monitor,
         id,
         index,
         started_at,
         timeout,
         attempt,
         limits,
         peak_memory
       ) do
    wait = poll_interval(started_at, timeout)

    receive do
      {^token, outcome, reductions, garbage_collections, final_memory} ->
        Process.demonitor(monitor, [:flush])
        memory = max(peak_memory, final_memory)

        cond do
          limit_exceeded?(final_memory, limits.max_memory_bytes) ->
            limited_result(
              id,
              index,
              started_at,
              attempt,
              memory,
              :memory,
              final_memory,
              limits.max_memory_bytes
            )

          limit_exceeded?(reductions, limits.max_reductions) ->
            limited_result(
              id,
              index,
              started_at,
              attempt,
              memory,
              :reductions,
              reductions,
              limits.max_reductions
            )

          true ->
            result(
              id,
              index,
              outcome,
              started_at,
              reductions,
              garbage_collections,
              attempt,
              memory
            )
        end

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        result(
          id,
          index,
          {:error, %{kind: :process_exit, code: "PF8105", reason: reason}},
          started_at,
          0,
          0,
          attempt,
          peak_memory
        )
    after
      wait ->
        {memory, reductions} = process_sample(pid)
        peak_memory = max(peak_memory, memory)

        cond do
          limit_exceeded?(memory, limits.max_memory_bytes) ->
            terminate_limited_job(pid, monitor)

            limited_result(
              id,
              index,
              started_at,
              attempt,
              peak_memory,
              :memory,
              memory,
              limits.max_memory_bytes
            )

          limit_exceeded?(reductions, limits.max_reductions) ->
            terminate_limited_job(pid, monitor)

            limited_result(
              id,
              index,
              started_at,
              attempt,
              peak_memory,
              :reductions,
              reductions,
              limits.max_reductions
            )

          timed_out?(started_at, timeout) ->
            terminate_limited_job(pid, monitor)

            %Result{
              id: id,
              index: index,
              status: :timeout,
              error: %{
                kind: :timeout,
                timeout: timeout,
                code: Error.timeout(:render, timeout).code
              },
              duration_us: elapsed_us(started_at),
              reductions: reductions,
              garbage_collections: 0,
              attempts: attempt,
              peak_memory_bytes: peak_memory
            }

          true ->
            receive_result(
              token,
              pid,
              monitor,
              id,
              index,
              started_at,
              timeout,
              attempt,
              limits,
              peak_memory
            )
        end
    end
  end

  defp result(
         id,
         index,
         outcome,
         started_at,
         reductions,
         garbage_collections,
         attempt,
         peak_memory
       ) do
    base = %Result{
      id: id,
      index: index,
      status: :ok,
      duration_us: elapsed_us(started_at),
      reductions: reductions,
      garbage_collections: garbage_collections,
      attempts: attempt,
      peak_memory_bytes: peak_memory
    }

    case outcome do
      {:ok, value} -> %{base | value: value}
      {:error, error} -> %{base | status: :error, error: error}
    end
  end

  defp elapsed_us(started_at) do
    System.convert_time_unit(System.monotonic_time() - started_at, :native, :microsecond)
  end

  defp execution_options(options, timeout) do
    %{
      timeout: timeout,
      max_attempts: Keyword.get(options, :max_attempts, 1),
      retry_delay: Keyword.get(options, :retry_delay, 0),
      retry_on: Keyword.get(options, :retry_on, [:error]),
      max_memory_bytes: Keyword.get(options, :max_memory_bytes, :infinity),
      max_reductions: Keyword.get(options, :max_reductions, :infinity),
      worker_heap_size: Keyword.get(options, :worker_heap_size, 233)
    }
  end

  defp validate_options!(max_concurrency, timeout, job_id, on_result, execution_options) do
    positive_integer!(max_concurrency, :max_concurrency)
    validate_timeout!(timeout)

    unless is_function(job_id, 2),
      do: raise(ArgumentError, "job_id must be a function of arity 2")

    unless is_function(on_result, 1),
      do: raise(ArgumentError, "on_result must be a function of arity 1")

    positive_integer!(execution_options.max_attempts, :max_attempts)
    positive_integer!(execution_options.worker_heap_size, :worker_heap_size)

    unless is_integer(execution_options.retry_delay) and execution_options.retry_delay >= 0,
      do: raise(ArgumentError, "retry_delay must be a non-negative integer")

    validate_retries!(execution_options.retry_on)

    Enum.each(
      [:max_memory_bytes, :max_reductions],
      &validate_limit!(Map.fetch!(execution_options, &1), &1)
    )
  end

  defp positive_integer!(value, _) when is_integer(value) and value > 0, do: :ok
  defp positive_integer!(_, key), do: raise(ArgumentError, "#{key} must be a positive integer")
  defp validate_timeout!(:infinity), do: :ok
  defp validate_timeout!(value) when is_integer(value) and value >= 0, do: :ok

  defp validate_timeout!(_),
    do: raise(ArgumentError, "timeout must be :infinity or a non-negative integer")

  defp validate_limit!(:infinity, _), do: :ok
  defp validate_limit!(value, key), do: positive_integer!(value, key)

  defp validate_retries!(values) when is_list(values) do
    unless Enum.all?(values, &(&1 in [:error, :timeout, :resource_limit, :cancelled])),
      do: raise(ArgumentError, "retry_on must contain supported failure statuses")
  end

  defp validate_retries!(_),
    do: raise(ArgumentError, "retry_on must be a list of failure statuses")

  defp poll_interval(_started_at, :infinity), do: 5

  defp poll_interval(started_at, timeout) do
    remaining = max(timeout * 1_000 - elapsed_us(started_at), 0)
    min(5, ceil(remaining / 1_000))
  end

  defp timed_out?(_started_at, :infinity), do: false
  defp timed_out?(started_at, timeout), do: elapsed_us(started_at) >= timeout * 1_000

  defp process_memory(pid) do
    case Process.info(pid, [:memory, :binary]) do
      [memory: bytes, binary: binaries] ->
        Enum.reduce(binaries, bytes, fn {_reference, size, _references}, total -> total + size end)

      nil ->
        0
    end
  end

  defp process_sample(pid) do
    case Process.info(pid, [:memory, :binary, :reductions]) do
      [memory: bytes, binary: binaries, reductions: reductions] ->
        {Enum.reduce(binaries, bytes, fn {_ref, size, _count}, total -> total + size end),
         reductions}

      nil ->
        {0, 0}
    end
  end

  defp limit_exceeded?(_value, :infinity), do: false
  defp limit_exceeded?(value, limit), do: value > limit

  defp terminate_limited_job(pid, monitor) do
    Process.unlink(pid)
    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
    end
  end

  defp limited_result(id, index, started_at, attempt, peak_memory, resource, value, limit) do
    %Result{
      id: id,
      index: index,
      status: :resource_limit,
      error: %{
        kind: :resource_limit,
        resource: resource,
        value: value,
        limit: limit,
        code: Error.resource_limit(resource, value, limit).code
      },
      duration_us: elapsed_us(started_at),
      reductions: if(resource == :reductions, do: value, else: 0),
      garbage_collections: 0,
      attempts: attempt,
      peak_memory_bytes: peak_memory
    }
  end

  defp emit_batch_complete(results, started_at, options) do
    {measurements, status_counts} =
      Enum.reduce(
        results,
        {%{jobs: 0, bytes: 0, memory: 0, reductions: 0, gc: 0}, %{}},
        fn result, {metrics, counts} ->
          {%{
             jobs: metrics.jobs + 1,
             bytes: metrics.bytes + result_bytes(result),
             memory: max(metrics.memory, result.peak_memory_bytes),
             reductions: metrics.reductions + result.reductions,
             gc: metrics.gc + result.garbage_collections
           }, Map.update(counts, result.status, 1, &(&1 + 1))}
        end
      )

    measurements = Map.put(measurements, :duration, System.monotonic_time() - started_at)

    metadata = %{
      status: if(Map.get(status_counts, :ok, 0) == measurements.jobs, do: :ok, else: :error),
      statuses: status_counts,
      max_concurrency: Keyword.get(options, :max_concurrency, System.schedulers_online()),
      ordered: Keyword.get(options, :ordered, true)
    }

    Telemetry.batch_complete(measurements, metadata)
  end

  defp result_bytes(%Result{status: :ok, value: value}) when is_binary(value),
    do: byte_size(value)

  defp result_bytes(%Result{status: :ok, value: %{pdf: pdf}}) when is_binary(pdf),
    do: byte_size(pdf)

  defp result_bytes(_result), do: 0
end
