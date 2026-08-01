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
    |> canonical()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical(map) when is_map(map),
    do: map |> Enum.map(fn {key, value} -> {key, canonical(value)} end) |> Enum.sort()

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)

  defp canonical(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&canonical/1) |> List.to_tuple()

  defp canonical(value), do: value
end
