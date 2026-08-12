defmodule PaperForge.PageTemplateError do
  defexception [:message, :template, :reason, :metadata]

  def exception(options) when is_list(options) do
    reason = Keyword.get(options, :reason, :page_template_error)

    %__MODULE__{
      message: message(reason, options),
      template: Keyword.get(options, :template),
      reason: reason,
      metadata: Keyword.get(options, :metadata, %{})
    }
  end

  defp message(:unknown_template, options) do
    "unknown page template #{inspect(Keyword.get(options, :template))}"
  end

  defp message(:template_cycle, options) do
    "page template inheritance cycle at #{inspect(Keyword.get(options, :template))}"
  end

  defp message(reason, _options) do
    "page template failed: #{inspect(reason)}"
  end
end
