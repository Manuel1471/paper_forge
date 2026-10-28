defmodule PaperForge.Declarative.Cache do
  @moduledoc false

  @key {__MODULE__, :entries}
  @limit 32

  @spec fetch(binary()) :: {:ok, term()} | :error
  def fetch(key) do
    case Process.get(@key, []) |> List.keyfind(key, 0) do
      {^key, value} -> {:ok, value}
      nil -> :error
    end
  end

  @spec put(binary(), term()) :: term()
  def put(key, value) do
    entries =
      [{key, value} | Process.get(@key, []) |> List.keydelete(key, 0)] |> Enum.take(@limit)

    Process.put(@key, entries)
    value
  end

  @spec clear() :: :ok
  def clear do
    Process.delete(@key)
    :ok
  end

  @spec hash(term()) :: binary()
  def hash(value) do
    value
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
