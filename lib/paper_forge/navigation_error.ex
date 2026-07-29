defmodule PaperForge.NavigationError do
  defexception [:message, :destination, :reason, :metadata]

  def exception(options) when is_list(options) do
    reason = Keyword.get(options, :reason, :navigation_error)

    %__MODULE__{
      message: message(reason, options),
      destination: Keyword.get(options, :destination),
      reason: reason,
      metadata: Keyword.get(options, :metadata, %{})
    }
  end

  defp message(:duplicate_destination, options) do
    "duplicate destination #{inspect(Keyword.get(options, :destination))}"
  end

  defp message(:unresolved_destination, options) do
    "unresolved destination #{inspect(Keyword.get(options, :destination))}"
  end

  defp message(reason, _options) do
    "navigation failed: #{inspect(reason)}"
  end
end
