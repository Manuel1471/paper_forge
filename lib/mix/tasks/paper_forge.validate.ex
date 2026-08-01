defmodule Mix.Tasks.PaperForge.Validate do
  use Mix.Task

  alias PaperForge.Declarative.LocationMap

  @shortdoc "Validates a .paperforge template and optional JSON data"

  @moduledoc """
  Validates a `.paperforge` file without generating a PDF.

      mix paper_forge.validate TEMPLATE [DATA.json]

  Options:

    * `--root PATH` - allowed root for imports and local resources
    * `--reject-unknown-data` - reject input keys absent from `variables`
  """

  @impl Mix.Task
  def run(arguments) do
    {options, positional, invalid} =
      OptionParser.parse(arguments,
        strict: [root: :string, reject_unknown_data: :boolean]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    case positional do
      [template_path | rest] when length(rest) <= 1 ->
        {data, data_options} = if rest == [], do: {%{}, []}, else: read_json!(List.first(rest))
        root = Keyword.get(options, :root, Path.dirname(Path.expand(template_path)))

        with {:ok, template} <- PaperForge.Declarative.load(template_path, root: root),
             :ok <-
               validate_template(
                 template,
                 data,
                 [
                   registry: PaperForge.Declarative.Registry.new(resource_root: root),
                   reject_unknown_data: Keyword.get(options, :reject_unknown_data, false)
                 ] ++ data_options
               ) do
          Mix.shell().info("Valid .paperforge template: #{template_path}")
        else
          {:error, errors} ->
            Enum.each(errors, &Mix.shell().error(format_error(&1)))
            Mix.raise(".paperforge validation failed")
        end

      _ ->
        Mix.raise("usage: mix paper_forge.validate TEMPLATE [DATA.json]")
    end
  end

  defp read_json!(path) do
    source = File.read!(path)

    case Jason.decode(source) do
      {:ok, data} when is_map(data) ->
        {data,
         [
           data_source: Path.expand(path),
           data_locations: LocationMap.build(source, Path.expand(path))
         ]}

      {:ok, _} ->
        Mix.raise("data JSON root must be an object")

      {:error, reason} ->
        Mix.raise("invalid data JSON: #{Exception.message(reason)}")
    end
  end

  defp validate_template(%{"kind" => "component"} = component, data, options) do
    props = Map.get(component, "props", %{})

    document =
      component
      |> Map.drop(["kind", "name", "props", "defaults", "slots", "variants"])
      |> Map.put("variables", props)

    values = if data == %{}, do: sample_values(props), else: data
    PaperForge.Declarative.validate(document, values, options)
  end

  defp validate_template(template, data, options),
    do: PaperForge.Declarative.validate(template, data, options)

  defp sample_values(schemas) do
    Map.new(schemas, fn {name, schema} -> {name, sample_value(schema)} end)
  end

  defp sample_value(schema) when is_binary(schema), do: sample_value(%{"type" => schema})

  defp sample_value(schema) do
    cond do
      Map.has_key?(schema, "default") ->
        schema["default"]

      is_list(schema["enum"]) and schema["enum"] != [] ->
        List.first(schema["enum"])

      schema["type"] == "string" ->
        String.duplicate("X", max(Map.get(schema, "min_length", 1), 1))

      schema["type"] == "number" ->
        Map.get(schema, "min", 0)

      schema["type"] == "integer" ->
        schema |> Map.get("min", 0) |> ceil()

      schema["type"] == "boolean" ->
        true

      schema["type"] == "list" ->
        List.duplicate(
          sample_value(Map.get(schema, "items", %{"type" => "any"})),
          Map.get(schema, "min_length", 0)
        )

      schema["type"] == "map" ->
        required = Map.get(schema, "required_properties", [])
        properties = Map.get(schema, "properties", %{})

        Map.new(required, fn name ->
          {name, sample_value(Map.get(properties, name, %{"type" => "any"}))}
        end)

      true ->
        nil
    end
  end

  defp format_error(error) do
    location =
      [error.source, error.line, error.column]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")

    prefix = if location == "", do: error.path, else: "#{location} #{error.path}"
    "#{prefix} [#{error.code}] #{error.message}"
  end
end
