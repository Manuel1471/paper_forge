defmodule PaperForge.PerformanceCache do
  @moduledoc false

  @cache_key {__MODULE__, :namespaces}
  @stats_key {__MODULE__, :stats}
  @default_limit 512

  @spec fetch(atom(), term(), (-> term()), pos_integer()) :: term()
  def fetch(namespace, key, producer, limit \\ @default_limit)
      when is_atom(namespace) and is_function(producer, 0) and is_integer(limit) and limit > 0 do
    caches = Process.get(@cache_key, %{})
    cache = Map.get(caches, namespace, new_cache())

    case cache.entries do
      %{^key => value} ->
        update_stats(namespace, :hits)
        value

      _ ->
        value = producer.()
        update_stats(namespace, :misses)

        updated_cache = put_entry(cache, key, value, limit)
        Process.put(@cache_key, Map.put(caches, namespace, updated_cache))
        value
    end
  end

  @spec reset() :: :ok
  def reset do
    Process.delete(@cache_key)
    Process.delete(@stats_key)
    :ok
  end

  @spec stats() :: map()
  def stats do
    Process.get(@stats_key, %{})
  end

  defp update_stats(namespace, field) do
    stats = Process.get(@stats_key, %{})
    namespace_stats = Map.get(stats, namespace, %{hits: 0, misses: 0})

    Process.put(
      @stats_key,
      Map.put(stats, namespace, Map.update!(namespace_stats, field, &(&1 + 1)))
    )
  end

  defp new_cache do
    %{entries: %{}, order: :queue.new()}
  end

  defp put_entry(cache, key, value, limit) do
    if map_size(cache.entries) >= limit do
      %{
        entries: %{key => value},
        order: :queue.in(key, :queue.new())
      }
    else
      %{
        entries: Map.put(cache.entries, key, value),
        order: :queue.in(key, cache.order)
      }
    end
  end
end
