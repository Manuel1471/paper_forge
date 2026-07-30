defmodule PaperForge.TelemetryTest do
  use ExUnit.Case, async: false

  alias PaperForge.Concurrent
  alias PaperForge.Page
  alias PaperForge.Telemetry

  setup do
    handler_id = "paper-forge-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        Telemetry.events(),
        &__MODULE__.handle_event/4,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "emits render start and stop with pages, bytes, and runtime measurements" do
    pdf =
      PaperForge.new()
      |> PaperForge.add_page(fn page ->
        Page.text(page, "Observed PDF", x: 72, y: 750)
      end)
      |> PaperForge.to_binary()

    assert_receive {:telemetry, [:paperforge, :render, :start], %{system_time: system_time},
                    %{pages: 1, output: :binary, status: :started}}

    assert is_integer(system_time)

    assert_receive {:telemetry, [:paperforge, :render, :stop], measurements,
                    %{pages: 1, output: :binary, status: :ok}}

    assert measurements.duration > 0
    assert measurements.bytes == byte_size(pdf)
    assert measurements.memory > 0
    assert measurements.reductions > 0
    assert measurements.gc >= 0
  end

  test "emits render exception metadata before reraising" do
    invalid_document = %{PaperForge.new() | root_reference: nil}

    assert_raise PaperForge.ValidationError, fn ->
      PaperForge.to_binary(invalid_document)
    end

    assert_receive {:telemetry, [:paperforge, :render, :start], _measurements,
                    %{status: :started}}

    assert_receive {:telemetry, [:paperforge, :render, :exception], measurements,
                    %{status: :error, kind: :error, reason: %PaperForge.ValidationError{}}}

    assert measurements.duration > 0
    assert measurements.bytes == 0
  end

  test "emits one job event per attempt and one completion event per collected batch" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    [result] =
      Concurrent.run(
        [:invoice],
        fn _job ->
          attempt = Agent.get_and_update(attempts, fn value -> {value + 1, value + 1} end)
          if attempt == 1, do: raise("temporary"), else: "pdf"
        end,
        max_attempts: 2,
        retry_delay: 1,
        job_id: fn job, _index -> job end
      )

    assert result.status == :ok
    assert result.attempts == 2

    assert_receive {:telemetry, [:paperforge, :batch, :job], first_measurements,
                    %{id: :invoice, attempt: 1, status: :error}}

    assert first_measurements.duration > 0

    assert_receive {:telemetry, [:paperforge, :batch, :job], second_measurements,
                    %{id: :invoice, attempt: 2, status: :ok}}

    assert second_measurements.bytes == 3

    assert_receive {:telemetry, [:paperforge, :batch, :complete], measurements,
                    %{status: :ok, statuses: %{ok: 1}, max_concurrency: max_concurrency}}

    assert max_concurrency == System.schedulers_online()
    assert measurements.jobs == 1
    assert measurements.bytes == 3
    assert measurements.duration > 0
  end

  test "reports page metadata for structured concurrent results" do
    [result] =
      Concurrent.run([:report], fn _job ->
        %{pdf: "%PDF", pages: 12}
      end)

    assert result.status == :ok

    assert_receive {:telemetry, [:paperforge, :batch, :job], %{bytes: 4},
                    %{pages: 12, status: :ok}}
  end

  def handle_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry, event, measurements, metadata})
  end
end
