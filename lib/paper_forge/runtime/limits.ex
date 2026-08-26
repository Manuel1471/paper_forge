defmodule PaperForge.Runtime.Limits do
  @moduledoc false

  alias PaperForge.Document
  alias PaperForge.LimitError
  alias PaperForge.Object
  alias PaperForge.Stream

  @defaults %{
    max_objects: 500_000,
    max_uncompressed_stream_bytes: 50_000_000,
    max_recursion_depth: 100
  }

  @type limits :: %{
          max_objects: pos_integer(),
          max_uncompressed_stream_bytes: pos_integer(),
          max_recursion_depth: pos_integer()
        }

  @spec defaults() :: limits()
  def defaults, do: @defaults

  @spec normalize(keyword() | map() | nil) :: limits()
  def normalize(options) when options in [nil, []], do: @defaults

  def normalize(options) when is_list(options) do
    options |> Map.new() |> normalize()
  end

  def normalize(options) when is_map(options) do
    unknown = Map.keys(options) -- Map.keys(@defaults)

    if unknown != [] do
      raise ArgumentError,
            "unsupported document limits: #{Enum.map_join(unknown, ", ", &inspect/1)}"
    end

    limits = Map.merge(@defaults, options)

    unless Enum.all?(limits, fn {_key, value} -> is_integer(value) and value > 0 end) do
      raise ArgumentError, "document limits must be positive integers"
    end

    limits
  end

  @spec writer_limits(Document.t(), keyword()) :: limits()
  def writer_limits(%Document{limits: document_limits}, options) do
    supplied =
      options
      |> Keyword.take(Map.keys(@defaults))
      |> Map.new()
      |> Map.merge(options |> Keyword.get(:limits, %{}) |> Map.new())

    normalize(Map.merge(document_limits, supplied))
  end

  @spec validate_document!(Document.t(), keyword()) :: :ok
  def validate_document!(%Document{} = document, options) do
    limits = writer_limits(document, options)
    object_count = map_size(document.objects)

    ensure!(:max_objects, object_count, limits.max_objects)

    Enum.each(document.objects, fn {_id, %Object{value: value}} ->
      validate_value!(value, 1, limits)
    end)

    :ok
  end

  defp validate_value!(%Stream{} = stream, depth, limits) do
    ensure!(:max_recursion_depth, depth, limits.max_recursion_depth)

    ensure!(
      :max_uncompressed_stream_bytes,
      IO.iodata_length(stream.data),
      limits.max_uncompressed_stream_bytes
    )

    validate_value!(stream.dictionary, depth + 1, limits)
  end

  defp validate_value!(value, depth, limits) when is_map(value) and not is_struct(value) do
    ensure!(:max_recursion_depth, depth, limits.max_recursion_depth)

    Enum.each(value, fn {key, nested} ->
      validate_value!(key, depth + 1, limits)
      validate_value!(nested, depth + 1, limits)
    end)
  end

  defp validate_value!(value, depth, limits) when is_list(value) do
    ensure!(:max_recursion_depth, depth, limits.max_recursion_depth)
    Enum.each(value, &validate_value!(&1, depth + 1, limits))
  end

  defp validate_value!(_value, _depth, _limits), do: :ok

  defp ensure!(_limit, actual, maximum) when actual <= maximum, do: :ok

  defp ensure!(limit, actual, maximum) do
    raise LimitError, limit: limit, actual: actual, maximum: maximum
  end
end
