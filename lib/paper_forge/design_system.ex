defmodule PaperForge.DesignSystem do
  @moduledoc """
  Immutable design-system registry for declarative PaperForge documents.

  A design system groups tokens, styles, visual components, shared layouts,
  and named themes. Themes may inherit from another theme and override only
  the values that differ.
  """

  defstruct tokens: %{}, styles: %{}, components: %{}, layouts: %{}, themes: %{}

  @type name :: atom() | binary()
  @type definition :: map()
  @type t :: %__MODULE__{
          tokens: map(),
          styles: map(),
          components: map(),
          layouts: map(),
          themes: map()
        }

  @spec new(keyword() | map()) :: t()
  def new(options \\ %{}) do
    options = Map.new(options)

    %__MODULE__{
      tokens: string_keys(Map.get(options, :tokens, Map.get(options, "tokens", %{}))),
      styles: string_keys(Map.get(options, :styles, Map.get(options, "styles", %{}))),
      components: string_keys(Map.get(options, :components, Map.get(options, "components", %{}))),
      layouts: string_keys(Map.get(options, :layouts, Map.get(options, "layouts", %{}))),
      themes: string_keys(Map.get(options, :themes, Map.get(options, "themes", %{})))
    }
  end

  @spec token(t(), name(), term()) :: t()
  def token(%__MODULE__{} = system, name, value),
    do: %{system | tokens: Map.put(system.tokens, to_string(name), value)}

  @spec style(t(), name(), map() | keyword()) :: t()
  def style(%__MODULE__{} = system, name, definition),
    do: %{
      system
      | styles: Map.put(system.styles, to_string(name), definition |> Map.new() |> string_keys())
    }

  @spec component(t(), name(), definition()) :: t()
  def component(%__MODULE__{} = system, name, definition) when is_map(definition),
    do: %{
      system
      | components: Map.put(system.components, to_string(name), string_keys(definition))
    }

  @spec layout(t(), name(), definition()) :: t()
  def layout(%__MODULE__{} = system, name, definition) when is_map(definition),
    do: %{system | layouts: Map.put(system.layouts, to_string(name), string_keys(definition))}

  @spec theme(t(), name(), definition()) :: t()
  def theme(%__MODULE__{} = system, name, definition) when is_map(definition),
    do: %{system | themes: Map.put(system.themes, to_string(name), string_keys(definition))}

  @doc "Merges two libraries. Values from `right` take precedence."
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = left, %__MODULE__{} = right) do
    %__MODULE__{
      tokens: deep_merge(left.tokens, right.tokens),
      styles: deep_merge(left.styles, right.styles),
      components: deep_merge(left.components, right.components),
      layouts: deep_merge(left.layouts, right.layouts),
      themes: deep_merge(left.themes, right.themes)
    }
  end

  @doc "Resolves a theme and its inheritance chain into a complete library."
  @spec resolve(t(), name() | nil) :: {:ok, t()} | {:error, term()}
  def resolve(%__MODULE__{} = system, nil), do: {:ok, system}

  def resolve(%__MODULE__{} = system, name) do
    with {:ok, overrides} <- resolve_theme(system.themes, to_string(name), MapSet.new()) do
      {:ok,
       %__MODULE__{
         system
         | tokens: deep_merge(system.tokens, Map.get(overrides, "tokens", %{})),
           styles: deep_merge(system.styles, Map.get(overrides, "styles", %{})),
           components: deep_merge(system.components, Map.get(overrides, "components", %{})),
           layouts: deep_merge(system.layouts, Map.get(overrides, "layouts", %{}))
       }}
    end
  end

  defp resolve_theme(themes, name, seen) do
    cond do
      MapSet.member?(seen, name) ->
        {:error, {:theme_cycle, name}}

      not Map.has_key?(themes, name) ->
        {:error, {:unknown_theme, name}}

      true ->
        theme = Map.fetch!(themes, name)

        case Map.get(theme, "extends") do
          nil ->
            {:ok, Map.delete(theme, "extends")}

          parent ->
            with {:ok, inherited} <-
                   resolve_theme(themes, to_string(parent), MapSet.put(seen, name)) do
              {:ok, deep_merge(inherited, Map.delete(theme, "extends"))}
            end
        end
    end
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value),
        do: deep_merge(left_value, right_value),
        else: right_value
    end)
  end

  defp string_keys(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), string_keys(item)} end)
  end

  defp string_keys(value) when is_list(value) do
    if value != [] and Keyword.keyword?(value),
      do: value |> Map.new() |> string_keys(),
      else: Enum.map(value, &string_keys/1)
  end

  defp string_keys(value), do: value
end
