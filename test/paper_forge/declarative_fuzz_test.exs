defmodule PaperForge.DeclarativeFuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias PaperForge.Declarative

  property "untrusted declarative identifiers never create BEAM atoms" do
    check all(suffix <- string(:alphanumeric, min_length: 8, max_length: 48), max_runs: 40) do
      identifier = "fuzz_#{suffix}_#{System.unique_integer([:positive])}"
      refute_existing_atom(identifier)
      refute_existing_atom(identifier <> "_style")
      refute_existing_atom(identifier <> "_template")

      template = %{
        "version" => "1",
        "design_system" => %{
          "styles" => %{(identifier <> "_style") => %{"size" => 11}}
        },
        "page_templates" => %{(identifier <> "_template") => %{}},
        "blocks" => [
          %{
            "type" => "paragraph",
            "text" => identifier,
            "options" => %{
              "style" => identifier <> "_style",
              "template" => identifier <> "_template"
            }
          }
        ]
      }

      assert {:ok, _compiled} = Declarative.compile(template, %{})
      refute_existing_atom(identifier)
      refute_existing_atom(identifier <> "_style")
      refute_existing_atom(identifier <> "_template")
    end
  end

  defp refute_existing_atom(value) do
    try do
      String.to_existing_atom(value)
      flunk("unexpected atom allocation for #{inspect(value)}")
    rescue
      ArgumentError -> :ok
    end
  end
end
