defmodule PaperForge.Import do
  @moduledoc """
  Converts interoperable source formats into PaperForge Layout IR.

  HTML and Markdown imports return `%PaperForge.Flow{}` values, so imported
  content uses the same measurement, pagination, navigation, and rendering
  engine as native authoring.
  """

  @doc "Imports an HTML fragment into Layout IR."
  @spec html(binary(), keyword()) :: {:ok, PaperForge.Flow.t()} | {:error, term()}
  defdelegate html(source, options \\ []), to: PaperForge.Import.HTML, as: :parse

  @doc "Imports CommonMark Markdown into Layout IR."
  @spec markdown(binary(), keyword()) :: {:ok, PaperForge.Flow.t()} | {:error, term()}
  defdelegate markdown(source, options \\ []), to: PaperForge.Import.Markdown, as: :parse
end
