defmodule PaperForge.Declarative.Expression do
  @moduledoc false

  @operators ~w(eq neq gt gte lt lte and or not contains empty)

  @spec evaluate(term(), map(), (map(), binary() -> term())) ::
          {:ok, boolean()} | {:error, term()}
  def evaluate(expression, context, lookup) when is_binary(expression),
    do: {:ok, truthy?(lookup.(context, expression))}

  def evaluate(%{"operator" => operator} = expression, context, lookup)
      when operator in @operators do
    evaluate_operator(operator, expression, context, lookup)
  end

  def evaluate(value, _context, _lookup) when is_boolean(value), do: {:ok, value}
  def evaluate(expression, _context, _lookup), do: {:error, {:invalid_expression, expression}}

  defp evaluate_operator("not", expression, context, lookup) do
    with {:ok, value} <- evaluate(Map.get(expression, "value"), context, lookup),
         do: {:ok, not value}
  end

  defp evaluate_operator(operator, expression, context, lookup) when operator in ["and", "or"] do
    values = Map.get(expression, "values", [])

    with results when is_list(results) <- Enum.map(values, &evaluate(&1, context, lookup)),
         nil <- Enum.find(results, &match?({:error, _}, &1)) do
      booleans = Enum.map(results, fn {:ok, value} -> value end)
      {:ok, if(operator == "and", do: Enum.all?(booleans), else: Enum.any?(booleans))}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp evaluate_operator("empty", expression, context, lookup) do
    {:ok, empty?(resolve(Map.get(expression, "value"), context, lookup))}
  end

  defp evaluate_operator("contains", expression, context, lookup) do
    left = resolve(Map.get(expression, "left"), context, lookup)
    right = resolve(Map.get(expression, "right"), context, lookup)

    {:ok,
     cond do
       is_binary(left) -> String.contains?(left, to_string(right))
       is_list(left) -> right in left
       is_map(left) -> Map.has_key?(left, right)
       true -> false
     end}
  end

  defp evaluate_operator(operator, expression, context, lookup) do
    left = resolve(Map.get(expression, "left"), context, lookup)
    right = resolve(Map.get(expression, "right"), context, lookup)

    result =
      case operator do
        "eq" -> left == right
        "neq" -> left != right
        "gt" -> comparable?(left, right) && left > right
        "gte" -> comparable?(left, right) && left >= right
        "lt" -> comparable?(left, right) && left < right
        "lte" -> comparable?(left, right) && left <= right
      end

    {:ok, result}
  end

  defp resolve("{{" <> _ = interpolation, context, lookup) do
    case Regex.run(~r/^\{\{\s*([\w.]+)\s*\}\}$/, interpolation) do
      [_, path] -> lookup.(context, path)
      _ -> interpolation
    end
  end

  defp resolve(value, _context, _lookup), do: value

  defp comparable?(left, right),
    do: (is_number(left) && is_number(right)) || (is_binary(left) && is_binary(right))

  defp empty?(value), do: value in [nil, "", []] || value == %{}
  defp truthy?(value), do: value not in [nil, false, 0, "", []]
end
