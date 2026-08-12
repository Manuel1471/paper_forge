defmodule PaperForge.Declarative.Registry do
  @moduledoc """
  Registry of trusted visual components and resource-access policy.

  Templates can invoke registered functions by name, but cannot define or
  evaluate executable code. Each component receives resolved props and slots
  and must return a `PaperForge.Flow`.
  """

  alias PaperForge.Flow

  defmodule Component do
    @moduledoc false
    defstruct [:renderer, props: %{}, variants: []]

    @type t :: %__MODULE__{renderer: function(), props: map(), variants: [binary()]}
  end

  defstruct components: %{},
            resource_root: nil,
            allowed_schemes: ["https"],
            max_resource_bytes: 20_000_000

  @type component :: struct()
  @type t :: %__MODULE__{
          components: %{optional(binary()) => component()},
          resource_root: Path.t() | nil,
          allowed_schemes: [binary()],
          max_resource_bytes: pos_integer()
        }

  @spec new(keyword()) :: t()
  def new(options \\ []) do
    %__MODULE__{
      resource_root: options |> Keyword.get(:resource_root) |> expand_root(),
      allowed_schemes: Keyword.get(options, :allowed_schemes, ["https"]),
      max_resource_bytes: Keyword.get(options, :max_resource_bytes, 20_000_000)
    }
  end

  @doc "Registers a trusted renderer accepting `(props, slots)` or `(props, slots, variant)`."
  @spec component(t(), atom() | binary(), function(), keyword()) :: t()
  def component(%__MODULE__{} = registry, name, renderer, options \\ [])
      when is_function(renderer, 2) or is_function(renderer, 3) do
    entry = %Component{
      renderer: renderer,
      props: options |> Keyword.get(:props, %{}) |> stringify(),
      variants: Enum.map(Keyword.get(options, :variants, []), &to_string/1)
    }

    %{registry | components: Map.put(registry.components, to_string(name), entry)}
  end

  @spec fetch_component(t(), binary()) :: {:ok, component()} | :error
  def fetch_component(%__MODULE__{} = registry, name),
    do: Map.fetch(registry.components, to_string(name))

  @spec render(component(), map(), map(), binary() | nil) ::
          {:ok, Flow.t()} | {:error, term()}
  def render(%Component{} = component, props, slots, variant) do
    cond do
      variant && component.variants != [] && variant not in component.variants ->
        {:error, {:unknown_variant, variant}}

      is_function(component.renderer, 3) ->
        normalize_render(component.renderer.(props, slots, variant))

      true ->
        normalize_render(component.renderer.(Map.put(props, "variant", variant), slots))
    end
  rescue
    exception -> {:error, {:component_exception, exception}}
  end

  @doc "Resolves a file or URL according to the registry resource policy."
  @spec resolve_resource(t(), binary()) :: {:ok, binary()} | {:error, term()}
  def resolve_resource(%__MODULE__{} = registry, source) when is_binary(source) do
    uri = URI.parse(source)

    cond do
      uri.scheme in registry.allowed_schemes ->
        {:ok, source}

      uri.scheme != nil ->
        {:error, {:forbidden_scheme, uri.scheme}}

      is_nil(registry.resource_root) ->
        {:error, :resource_root_required}

      true ->
        path = Path.expand(source, registry.resource_root)

        with :ok <- inside_root(path, registry.resource_root),
             :ok <- no_symlink(path, registry.resource_root),
             {:ok, stat} <- File.stat(path),
             :ok <- size_allowed(stat.size, registry.max_resource_bytes) do
          {:ok, path}
        end
    end
  end

  defp normalize_render(%Flow{} = flow), do: {:ok, flow}
  defp normalize_render(other), do: {:error, {:invalid_component_result, other}}

  defp inside_root(path, root) do
    expanded_path = Path.expand(path)
    expanded_root = Path.expand(root)
    root_prefix = expanded_root <> "/"

    if expanded_path == expanded_root or String.starts_with?(expanded_path, root_prefix),
      do: :ok,
      else: {:error, :outside_root}
  end

  defp size_allowed(size, maximum) when size <= maximum, do: :ok
  defp size_allowed(size, maximum), do: {:error, {:resource_too_large, size, maximum}}

  defp no_symlink(path, root) do
    path
    |> Path.relative_to(root)
    |> Path.split()
    |> Enum.reduce_while(root, fn segment, current ->
      candidate = Path.join(current, segment)

      case File.lstat(candidate) do
        {:ok, %File.Stat{type: :symlink}} -> {:halt, {:error, :symlink_not_allowed}}
        {:ok, _stat} -> {:cont, candidate}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      _path -> :ok
    end
  end

  defp expand_root(nil), do: nil
  defp expand_root(root), do: Path.expand(root)

  defp stringify(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), stringify(item)} end)

  defp stringify(value) when is_list(value), do: Enum.map(value, &stringify/1)
  defp stringify(value), do: value
end
