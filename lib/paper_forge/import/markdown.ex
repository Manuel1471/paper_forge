defmodule PaperForge.Import.Markdown do
  @moduledoc "Imports CommonMark Markdown into PaperForge Layout IR."

  alias PaperForge.Import.Markup

  @spec parse(binary(), keyword()) :: {:ok, PaperForge.Flow.t()} | {:error, term()}
  def parse(source, options \\ []) when is_binary(source) do
    case EarmarkParser.as_ast(source) do
      {:ok, ast, _messages} -> Markup.to_flow(Enum.map(ast, &normalize/1), options)
      {:error, _ast, messages} -> {:error, {:invalid_markdown, messages}}
    end
  end

  defp normalize({tag, attrs, children, _meta}) do
    %{
      tag: tag,
      attrs: Map.new(attrs),
      children: Enum.map(children, &normalize/1),
      text: nil,
      raw: nil
    }
  end

  defp normalize(text) when is_binary(text),
    do: %{tag: "#text", attrs: %{}, children: [], text: text, raw: nil}
end
