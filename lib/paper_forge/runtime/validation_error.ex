defmodule PaperForge.ValidationError do
  @moduledoc """
  Raised when a document fails structural validation before serialization.
  """

  defexception [:issues, message: "invalid PDF document structure"]

  @impl true
  def exception(issues) when is_list(issues) do
    details =
      Enum.map_join(issues, "; ", fn issue ->
        issue
        |> Map.take([:code, :object_id, :reference, :expected, :actual])
        |> inspect()
      end)

    %__MODULE__{issues: issues, message: "invalid PDF document structure: " <> details}
  end
end
