defmodule PaperForge.Declarative.Migration do
  @moduledoc "Version migration helpers for `.paperforge` templates."

  @current "1"

  @spec current_version() :: binary()
  def current_version, do: @current

  @spec migrate(map(), binary()) :: {:ok, map()} | {:error, term()}
  def migrate(template, target \\ @current)
  def migrate(%{"version" => version} = template, version), do: {:ok, template}

  def migrate(%{"version" => "0"} = template, "1") do
    migrated =
      template
      |> Map.put("version", "1")
      |> rename("schema", "variables")
      |> rename("content", "blocks")

    {:ok, migrated}
  end

  def migrate(%{"version" => version}, target),
    do: {:error, {:unsupported_migration, version, target}}

  def migrate(template, "1"), do: {:ok, Map.put(template, "version", "1")}

  defp rename(map, old, new) do
    case Map.pop(map, old) do
      {nil, map} -> map
      {value, map} -> Map.put_new(map, new, value)
    end
  end
end
