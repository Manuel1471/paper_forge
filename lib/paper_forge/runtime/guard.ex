defmodule PaperForge.Runtime.Guard do
  @moduledoc false

  alias PaperForge.Error

  @spec run(atom(), (-> term()), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def run(operation, function, options \\ [])
      when is_atom(operation) and is_function(function, 0) do
    timeout = Keyword.get(options, :timeout, :infinity)

    unless timeout == :infinity or (is_integer(timeout) and timeout >= 0) do
      raise ArgumentError, "timeout must be :infinity or a non-negative integer"
    end

    parent = self()
    token = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        result =
          try do
            {:ok, function.()}
          rescue
            exception ->
              {:error,
               %Error{
                 code: "PF8105",
                 category: :runtime,
                 operation: operation,
                 message: Exception.message(exception),
                 details: %{exception: exception, stacktrace: __STACKTRACE__}
               }}
          catch
            kind, reason ->
              {:error,
               %Error{
                 code: "PF8105",
                 category: :runtime,
                 operation: operation,
                 message: "#{kind}: #{inspect(reason)}",
                 details: %{kind: kind, reason: reason, stacktrace: __STACKTRACE__}
               }}
          end

        send(parent, {token, result})
      end)

    await(
      token,
      pid,
      monitor,
      operation,
      timeout,
      Keyword.get(options, :on_timeout, fn -> :ok end)
    )
  end

  defp await(token, pid, monitor, operation, timeout, on_timeout) do
    receive do
      {^token, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        {:error,
         %Error{
           code: "PF8105",
           category: :runtime,
           operation: operation,
           message: "#{operation} worker exited: #{inspect(reason)}",
           details: %{reason: reason}
         }}
    after
      timeout ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
        end

        on_timeout.()
        {:error, Error.timeout(operation, timeout)}
    end
  end
end
