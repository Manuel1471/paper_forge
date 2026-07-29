defmodule PaperForge.TableError do
  defexception [:message, :block_id, :row, :column, :reason, :metadata]

  def exception(options) when is_list(options) do
    reason = Keyword.get(options, :reason, :table_error)

    %__MODULE__{
      message: message(reason, options),
      block_id: Keyword.get(options, :block_id),
      row: Keyword.get(options, :row),
      column: Keyword.get(options, :column),
      reason: reason,
      metadata: Keyword.get(options, :metadata, %{})
    }
  end

  defp message(:row_too_large, options) do
    "table row #{inspect(Keyword.get(options, :row))} is too large to fit"
  end

  defp message(reason, _options) do
    "table layout failed: #{inspect(reason)}"
  end
end
