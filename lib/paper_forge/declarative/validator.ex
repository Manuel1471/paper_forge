defmodule PaperForge.Declarative.Validator do
  @moduledoc false

  alias PaperForge.Declarative.Error
  alias PaperForge.Declarative.Registry

  @root_fields MapSet.new(~w(
    version id variables document metadata layout_options page_templates design_system
    theme layout blocks imports includes libraries components kind name props defaults slots
    security signature protection compliance
    variants __source__ __root__ __locations__
  ))
  @variable_fields MapSet.new(~w(
    type required default min max min_length max_length pattern enum items properties
    required_properties additional_properties format
  ))
  @control_fields MapSet.new(~w(if then else for blocks component props slots variant slot))
  @block_fields MapSet.new(
                  ~w(type text content options columns rows min_rows max_rows cells count paragraphs)
                )
  @types ~w(any string number integer boolean list map)
  @formats ~w(url color file)
  @security_fields MapSet.new(~w(algorithm encrypt_metadata permissions))
  @permission_fields MapSet.new(~w(print copy modify extract))
  @signature_fields MapSet.new(
                      ~w(algorithm reason location contact_info timestamp tsa_url visible multiple)
                    )
  @protection_fields MapSet.new(~w(identifier modified_at watermark policy))
  @watermark_fields MapSet.new(~w(text opacity size color angle))
  @policy_fields MapSet.new(
                   ~w(allowed_uri_schemes allowed_hosts allow_attachments max_attachments max_attachment_bytes allowed_attachment_mimes)
                 )
  @compliance_fields MapSet.new(~w(profiles language title icc_profile output_condition))

  @spec validate(map(), map(), keyword()) :: {:ok, map()} | {:error, [Error.t()]}
  def validate(template, data, options \\ []) do
    registry = Keyword.get(options, :registry, Registry.new())

    errors =
      unknown_keys(template, @root_fields, "$", :unknown_root_field) ++
        component_file_errors(template) ++
        policy_errors(template) ++
        variable_definition_errors(Map.get(template, "variables", %{})) ++
        block_errors(Map.get(template, "blocks", []), "$.blocks")

    {values, data_errors} =
      validate_variables(Map.get(template, "variables", %{}), data, registry)

    extra_errors =
      if Keyword.get(options, :reject_unknown_data, false) do
        data
        |> Map.keys()
        |> Enum.reject(&Map.has_key?(Map.get(template, "variables", %{}), &1))
        |> Enum.map(&error(:unknown_data, "$.data.#{&1}", "undeclared input variable"))
      else
        []
      end

    case errors ++ data_errors ++ extra_errors do
      [] -> {:ok, values}
      issues -> {:error, issues}
    end
  end

  @spec validate_value(term(), map(), binary(), Registry.t()) :: [Error.t()]
  def validate_value(value, definition, path, registry) when is_map(definition) do
    type = Map.get(definition, "type", "any")

    if valid_type?(value, type) do
      constraint_errors(value, definition, path, registry)
    else
      [error(:invalid_type, path, "expected #{type}", value)]
    end
  end

  defp validate_variables(definitions, data, registry) do
    Enum.reduce(definitions, {data, []}, fn {name, raw_definition}, {values, errors} ->
      definition =
        if is_map(raw_definition), do: raw_definition, else: %{"type" => raw_definition}

      present? = Map.has_key?(values, name)
      value = Map.get(values, name, Map.get(definition, "default"))
      path = "$.data.#{name}"

      cond do
        not present? and Map.get(definition, "required", false) and
            not Map.has_key?(definition, "default") ->
          {values, errors ++ [error(:required, path, "required variable is missing")]}

        is_nil(value) ->
          {Map.put(values, name, nil), errors}

        true ->
          {Map.put(values, name, value),
           errors ++ validate_value(value, definition, path, registry)}
      end
    end)
  end

  defp policy_errors(template) do
    security = Map.get(template, "security", %{})
    signature = Map.get(template, "signature", %{})
    protection = Map.get(template, "protection", %{})
    compliance = Map.get(template, "compliance", %{})

    object_errors(security, @security_fields, "$.security", :invalid_security) ++
      object_errors(
        nested_object(security, "permissions"),
        @permission_fields,
        "$.security.permissions",
        :invalid_permissions
      ) ++
      object_errors(signature, @signature_fields, "$.signature", :invalid_signature) ++
      object_errors(protection, @protection_fields, "$.protection", :invalid_protection) ++
      object_errors(
        nested_object(protection, "policy"),
        @policy_fields,
        "$.protection.policy",
        :invalid_policy
      ) ++
      watermark_errors(nested_value(protection, "watermark")) ++
      object_errors(compliance, @compliance_fields, "$.compliance", :invalid_compliance)
  end

  defp object_errors(value, fields, path, _code) when is_map(value),
    do: unknown_keys(value, fields, path, :unknown_policy_field)

  defp object_errors(_value, _fields, path, code), do: [error(code, path, "must be an object")]

  defp watermark_errors(nil), do: []
  defp watermark_errors(value) when is_binary(value), do: []

  defp watermark_errors(value) when is_map(value),
    do: unknown_keys(value, @watermark_fields, "$.protection.watermark", :unknown_policy_field)

  defp watermark_errors(_value),
    do: [error(:invalid_watermark, "$.protection.watermark", "must be text or an object")]

  defp nested_object(value, key) when is_map(value), do: Map.get(value, key, %{})
  defp nested_object(_value, _key), do: %{}
  defp nested_value(value, key) when is_map(value), do: Map.get(value, key)
  defp nested_value(_value, _key), do: nil

  defp constraint_errors(value, definition, path, registry) do
    []
    |> length_errors(value, definition, path)
    |> numeric_errors(value, definition, path)
    |> pattern_errors(value, definition, path)
    |> enum_errors(value, definition, path)
    |> item_errors(value, definition, path, registry)
    |> property_errors(value, definition, path, registry)
    |> format_errors(value, definition, path, registry)
  end

  defp length_errors(errors, value, definition, path) when is_binary(value) or is_list(value) do
    length = if is_binary(value), do: String.length(value), else: Kernel.length(value)

    errors
    |> maybe(
      length < Map.get(definition, "min_length", 0),
      :min_length,
      path,
      "is shorter than min_length"
    )
    |> maybe(
      Map.has_key?(definition, "max_length") && length > definition["max_length"],
      :max_length,
      path,
      "is longer than max_length"
    )
  end

  defp length_errors(errors, _value, _definition, _path), do: errors

  defp numeric_errors(errors, value, definition, path) when is_number(value) do
    errors
    |> maybe(
      Map.has_key?(definition, "min") && value < definition["min"],
      :minimum,
      path,
      "is below minimum"
    )
    |> maybe(
      Map.has_key?(definition, "max") && value > definition["max"],
      :maximum,
      path,
      "is above maximum"
    )
  end

  defp numeric_errors(errors, _value, _definition, _path), do: errors

  defp pattern_errors(errors, value, %{"pattern" => pattern}, path) when is_binary(value) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        maybe(errors, not Regex.match?(regex, value), :pattern, path, "does not match pattern")

      {:error, reason} ->
        errors ++ [error(:invalid_pattern, path, "schema pattern is invalid", reason)]
    end
  end

  defp pattern_errors(errors, _value, _definition, _path), do: errors

  defp enum_errors(errors, value, %{"enum" => allowed}, path) when is_list(allowed),
    do: maybe(errors, value not in allowed, :enum, path, "is not an allowed value")

  defp enum_errors(errors, _value, _definition, _path), do: errors

  defp item_errors(errors, value, %{"items" => schema}, path, registry)
       when is_list(value) and is_map(schema) do
    value
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {item, index}, acc ->
      acc ++ validate_value(item, schema, "#{path}[#{index}]", registry)
    end)
  end

  defp item_errors(errors, _value, _definition, _path, _registry), do: errors

  defp property_errors(errors, value, definition, path, registry) when is_map(value) do
    properties = Map.get(definition, "properties", %{})
    required = Map.get(definition, "required_properties", [])

    errors =
      Enum.reduce(required, errors, fn name, acc ->
        maybe(
          acc,
          not Map.has_key?(value, name),
          :required_property,
          "#{path}.#{name}",
          "required property is missing"
        )
      end)

    errors =
      Enum.reduce(properties, errors, fn {name, schema}, acc ->
        if Map.has_key?(value, name),
          do: acc ++ validate_value(Map.get(value, name), schema, "#{path}.#{name}", registry),
          else: acc
      end)

    if Map.get(definition, "additional_properties", true) do
      errors
    else
      unknown = Map.keys(value) -- Map.keys(properties)

      errors ++
        Enum.map(unknown, &error(:unknown_property, "#{path}.#{&1}", "property is not declared"))
    end
  end

  defp property_errors(errors, _value, _definition, _path, _registry), do: errors

  defp format_errors(errors, value, %{"format" => "url"}, path, registry) when is_binary(value) do
    case Registry.resolve_resource(registry, value) do
      {:ok, _} -> errors
      {:error, reason} -> errors ++ [error(:invalid_url, path, "URL is not allowed", reason)]
    end
  end

  defp format_errors(errors, value, %{"format" => "file"}, path, registry)
       when is_binary(value) do
    case Registry.resolve_resource(registry, value) do
      {:ok, resolved} ->
        if URI.parse(resolved).scheme,
          do: errors ++ [error(:invalid_file, path, "expected local file")],
          else: errors

      {:error, reason} ->
        errors ++ [error(:invalid_file, path, "file is not allowed", reason)]
    end
  end

  defp format_errors(errors, value, %{"format" => "color"}, path, _registry)
       when is_binary(value) do
    maybe(
      errors,
      not Regex.match?(~r/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/, value),
      :invalid_color,
      path,
      "expected #RGB or #RRGGBB"
    )
  end

  defp format_errors(errors, _value, _definition, _path, _registry), do: errors

  defp variable_definition_errors(definitions) when is_map(definitions) do
    Enum.flat_map(definitions, fn {name, definition} ->
      if is_map(definition) do
        type = Map.get(definition, "type", "any")

        unknown_keys(definition, @variable_fields, "$.variables.#{name}", :unknown_schema_field) ++
          if(type in @types,
            do: [],
            else: [
              error(
                :unknown_type,
                "$.variables.#{name}.type",
                "unsupported type #{inspect(type)}"
              )
            ]
          ) ++
          if(Map.get(definition, "format") in [nil | @formats],
            do: [],
            else: [error(:unknown_format, "$.variables.#{name}.format", "unsupported format")]
          )
      else
        if definition in @types,
          do: [],
          else: [
            error(:invalid_schema, "$.variables.#{name}", "schema must be an object or type name")
          ]
      end
    end)
  end

  defp variable_definition_errors(_), do: []

  defp component_file_errors(%{"kind" => "component"} = template) do
    errors =
      if is_binary(Map.get(template, "name")) and Map.get(template, "name") != "",
        do: [],
        else: [error(:invalid_component_name, "$.name", "component name must be a string")]

    errors ++
      variable_definition_errors(Map.get(template, "props", %{})) ++
      component_slot_definition_errors(Map.get(template, "slots", %{}), "$.slots") ++
      component_variant_errors(Map.get(template, "variants", %{}), "$.variants")
  end

  defp component_file_errors(%{"kind" => kind}),
    do: [error(:invalid_kind, "$.kind", "unsupported template kind #{inspect(kind)}")]

  defp component_file_errors(_template), do: []

  defp component_slot_definition_errors(slots, path) when is_map(slots) do
    Enum.flat_map(slots, fn {name, definition} ->
      if is_map(definition) and Map.keys(definition) -- ["required"] == [],
        do: [],
        else: [error(:invalid_slot_schema, "#{path}.#{name}", "slot schema is invalid")]
    end)
  end

  defp component_slot_definition_errors(_slots, path),
    do: [error(:invalid_slot_schema, path, "slots must be an object")]

  defp component_variant_errors(variants, path) when is_map(variants) do
    Enum.flat_map(variants, fn {name, definition} ->
      if is_map(definition),
        do: block_errors(Map.get(definition, "blocks", []), "#{path}.#{name}.blocks"),
        else: [error(:invalid_variant, "#{path}.#{name}", "variant must be an object")]
    end)
  end

  defp component_variant_errors(_variants, path),
    do: [error(:invalid_variant, path, "variants must be an object")]

  defp block_errors(blocks, path) when is_list(blocks) do
    blocks
    |> Enum.with_index()
    |> Enum.flat_map(fn {node, index} -> node_errors(node, "#{path}[#{index}]") end)
  end

  defp block_errors(_blocks, path), do: [error(:invalid_blocks, path, "blocks must be a list")]

  defp node_errors(node, path) when is_map(node) do
    allowed = MapSet.union(@control_fields, @block_fields)
    errors = unknown_keys(node, allowed, path, :unknown_block_field)

    nested =
      cond do
        Map.has_key?(node, "if") ->
          block_errors(Map.get(node, "then", []), "#{path}.then") ++
            block_errors(Map.get(node, "else", []), "#{path}.else")

        Map.has_key?(node, "for") ->
          block_errors(Map.get(node, "blocks", []), "#{path}.blocks")

        Map.has_key?(node, "component") ->
          slot_errors(Map.get(node, "slots", %{}), "#{path}.slots")

        Map.has_key?(node, "slot") ->
          []

        Map.has_key?(node, "type") ->
          []

        true ->
          [error(:invalid_block, path, "block must define type, component, if, or for")]
      end

    errors ++ nested
  end

  defp node_errors(_node, path), do: [error(:invalid_block, path, "block must be an object")]

  defp slot_errors(slots, path) when is_map(slots),
    do: Enum.flat_map(slots, fn {name, blocks} -> block_errors(blocks, "#{path}.#{name}") end)

  defp slot_errors(_slots, path), do: [error(:invalid_slots, path, "slots must be an object")]

  defp unknown_keys(map, allowed, path, code) do
    map
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(allowed, &1))
    |> Enum.map(&error(code, "#{path}.#{&1}", "unknown property"))
  end

  defp valid_type?(_value, "any"), do: true
  defp valid_type?(value, "string"), do: is_binary(value)
  defp valid_type?(value, "number"), do: is_number(value)
  defp valid_type?(value, "integer"), do: is_integer(value)
  defp valid_type?(value, "boolean"), do: is_boolean(value)
  defp valid_type?(value, "list"), do: is_list(value)
  defp valid_type?(value, "map"), do: is_map(value)
  defp valid_type?(_value, _type), do: false

  defp maybe(errors, true, code, path, message), do: errors ++ [error(code, path, message)]
  defp maybe(errors, false, _code, _path, _message), do: errors
  defp error(code, path, message, details \\ nil), do: Error.new(code, path, message, details)
end
