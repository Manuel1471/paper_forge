defmodule PaperForge.LayoutError do
  defexception [:message, :block_id, :page_number, :block_type, :reason, :metadata]

  def exception(options) when is_list(options) do
    reason = Keyword.get(options, :reason, :layout_error)

    %__MODULE__{
      message: message(reason, options),
      block_id: Keyword.get(options, :block_id),
      page_number: Keyword.get(options, :page_number),
      block_type: Keyword.get(options, :block_type),
      reason: reason,
      metadata: Keyword.get(options, :metadata, %{})
    }
  end

  defp message(:block_too_large, options) do
    "layout block #{inspect(Keyword.get(options, :block_id))} is too large " <>
      "for page #{inspect(Keyword.get(options, :page_number))}"
  end

  defp message(reason, _options) do
    "layout failed: #{inspect(reason)}"
  end
end
