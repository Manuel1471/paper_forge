defmodule PaperForge.ConcurrentTest do
  use ExUnit.Case, async: false

  alias PaperForge.Concurrent
  alias PaperForge.Concurrent.Result
  alias PaperForge.Page

  test "limits concurrency and preserves backpressure" do
    {:ok, counter} = Agent.start_link(fn -> %{current: 0, maximum: 0} end)

    results =
      Concurrent.run(
        1..24,
        fn value ->
          Agent.update(counter, fn state ->
            current = state.current + 1
            %{current: current, maximum: max(state.maximum, current)}
          end)

          Process.sleep(5)
          Agent.update(counter, &%{&1 | current: &1.current - 1})
          value * 2
        end,
        max_concurrency: 3
      )

    assert Agent.get(counter, & &1.maximum) == 3
    assert Enum.map(results, & &1.value) == Enum.map(1..24, &(&1 * 2))
    assert Enum.all?(results, &(&1.status == :ok))
  end

  test "isolates exceptions by document and reports metrics" do
    results =
      Concurrent.run(
        [:first, :broken, :last],
        fn
          :broken -> raise "render failed"
          value -> value
        end,
        max_concurrency: 2,
        job_id: fn job, _index -> job end
      )

    assert [%Result{status: :ok}, %Result{status: :error}, %Result{status: :ok}] = results
    assert Enum.map(results, & &1.id) == [:first, :broken, :last]
    assert Enum.at(results, 1).error.kind == :exception
    assert Enum.all?(results, &(&1.duration_us >= 0))
    assert Enum.all?(results, &(&1.reductions >= 0))
  end

  test "times out individual jobs without stopping the batch" do
    results =
      Concurrent.run(
        [:slow, :fast],
        fn
          :slow ->
            Process.sleep(100)
            :late

          :fast ->
            :ready
        end,
        timeout: 10,
        max_concurrency: 2
      )

    assert [%Result{status: :timeout}, %Result{status: :ok, value: :ready}] = results
  end

  test "uses a caller-owned Task.Supervisor and supports cancellation" do
    start_supervised!({Task.Supervisor, name: PaperForge.ConcurrentTest.Supervisor})

    task =
      Concurrent.start_job(
        PaperForge.ConcurrentTest.Supervisor,
        :job,
        fn _job ->
          Process.sleep(:infinity)
        end
      )

    assert Concurrent.cancel(task, 10) in [nil, {:exit, :shutdown}, {:exit, :killed}]
    refute Process.alive?(task.pid)
  end

  test "invokes the result callback for every completed job" do
    {:ok, collected} = Agent.start_link(fn -> [] end)

    results =
      Concurrent.run(1..8, &(&1 * &1),
        on_result: fn result -> Agent.update(collected, &[result.id | &1]) end
      )

    assert length(results) == 8
    assert Agent.get(collected, &length/1) == 8
  end

  test "retries isolated failures up to the configured attempt limit" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    [result] =
      Concurrent.run(
        [:job],
        fn _job ->
          attempt = Agent.get_and_update(attempts, fn current -> {current + 1, current + 1} end)
          if attempt == 1, do: raise("temporary failure"), else: :recovered
        end,
        max_attempts: 2,
        retry_delay: 1
      )

    assert result.status == :ok
    assert result.value == :recovered
    assert result.attempts == 2
  end

  test "terminates a job that exceeds its memory budget" do
    [result] =
      Concurrent.run(
        [:job],
        fn _job ->
          data = Enum.to_list(1..500_000)
          Process.sleep(50)
          length(data)
        end,
        max_memory_bytes: 500_000,
        timeout: 1_000
      )

    assert result.status == :resource_limit
    assert result.error.resource == :memory
    assert result.peak_memory_bytes > 500_000
  end

  test "terminates a job that exceeds its reductions budget" do
    [result] =
      Concurrent.run([:job], fn _job -> burn_reductions() end,
        max_reductions: 10_000,
        timeout: 1_000
      )

    assert result.status == :resource_limit
    assert result.error.resource == :reductions
    assert result.reductions > 10_000
  end

  @tag timeout: 30_000
  test "renders hundreds of isolated PDFs" do
    results =
      Concurrent.run(
        1..250,
        fn index ->
          PaperForge.new()
          |> PaperForge.add_page(fn page ->
            Page.text(page, "Concurrent PDF #{index}", x: 72, y: 750)
          end)
          |> PaperForge.to_binary()
        end,
        max_concurrency: 8,
        timeout: 5_000
      )

    assert length(results) == 250
    assert Enum.all?(results, &(&1.status == :ok))
    assert Enum.all?(results, &String.starts_with?(&1.value, "%PDF-1.7"))
    assert Enum.all?(results, &(&1.duration_us > 0))
  end

  defp burn_reductions, do: burn_reductions()
end
