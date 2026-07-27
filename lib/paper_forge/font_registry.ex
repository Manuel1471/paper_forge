defmodule PaperForge.FontRegistry do
  @moduledoc """
  Stores the standard PDF fonts registered in a document.

  Each font is registered only once. Repeated uses of the same font
  reuse both its internal resource name and its indirect object
  reference.

  Resource names are generated sequentially:

      F1
      F2
      F3
  """

  alias PaperForge.Font
  alias PaperForge.Fonts.Builtin
  alias PaperForge.Reference

  defstruct fonts: %{},
            next_resource_id: 1

  @type t :: %__MODULE__{
          fonts: %{optional(atom()) => Font.t()},
          next_resource_id: pos_integer()
        }

  @doc """
  Creates an empty font registry.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Returns whether a font has already been registered.
  """
  @spec registered?(t(), atom()) :: boolean()
  def registered?(
        %__MODULE__{} = registry,
        font_key
      )
      when is_atom(font_key) do
    Map.has_key?(
      registry.fonts,
      font_key
    )
  end

  @doc """
  Fetches a registered font.

  Returns `{:ok, font}` or `:error`.
  """
  @spec fetch(t(), atom()) ::
          {:ok, Font.t()}
          | :error
  def fetch(
        %__MODULE__{} = registry,
        font_key
      )
      when is_atom(font_key) do
    Map.fetch(
      registry.fonts,
      font_key
    )
  end

  @doc """
  Fetches a registered font and raises when it does not exist.
  """
  @spec fetch!(t(), atom()) :: Font.t()
  def fetch!(
        %__MODULE__{} = registry,
        font_key
      )
      when is_atom(font_key) do
    case fetch(
           registry,
           font_key
         ) do
      {:ok, font} ->
        font

      :error ->
        raise ArgumentError,
              "font #{inspect(font_key)} has not been registered"
    end
  end

  @doc """
  Registers a built-in PDF font.

  The reference must point to the font dictionary previously added to
  the PDF document.

  When the font already exists, the registry and existing font are
  returned unchanged.

  ## Example

      {registry, font} =
        PaperForge.FontRegistry.register(
          registry,
          :helvetica_bold,
          reference
        )

      font.resource_name
      #=> "F1"
  """
  @spec register(
          t(),
          atom(),
          Reference.t()
        ) ::
          {t(), Font.t()}
  def register(
        %__MODULE__{} = registry,
        font_key,
        %Reference{} = reference
      )
      when is_atom(font_key) do
    case fetch(
           registry,
           font_key
         ) do
      {:ok, font} ->
        {
          registry,
          font
        }

      :error ->
        create_font(
          registry,
          font_key,
          reference
        )
    end
  end

  @doc """
  Adds a fully built font to the registry.
  """
  @spec put(t(), Font.t()) :: {t(), Font.t()}
  def put(
        %__MODULE__{} = registry,
        %Font{} = font
      ) do
    case fetch(registry, font.key) do
      {:ok, existing_font} ->
        {registry, existing_font}

      :error ->
        updated_registry = %{
          registry
          | fonts:
              Map.put(
                registry.fonts,
                font.key,
                font
              ),
            next_resource_id: registry.next_resource_id + 1
        }

        {updated_registry, font}
    end
  end

  @doc """
  Replaces an already registered font without changing resource numbering.
  """
  @spec replace(t(), Font.t()) :: t()
  def replace(
        %__MODULE__{} = registry,
        %Font{} = font
      ) do
    %{
      registry
      | fonts:
          Map.put(
            registry.fonts,
            font.key,
            font
          )
    }
  end

  @doc """
  Returns all registered fonts sorted by their resource identifier.
  """
  @spec all(t()) :: [Font.t()]
  def all(%__MODULE__{} = registry) do
    registry.fonts
    |> Map.values()
    |> Enum.sort_by(&resource_number/1)
  end

  @doc """
  Returns all registered font keys.
  """
  @spec keys(t()) :: [atom()]
  def keys(%__MODULE__{} = registry) do
    registry
    |> all()
    |> Enum.map(& &1.key)
  end

  @doc """
  Creates a PDF `/Font` resource dictionary for selected fonts.

  ## Example result

      %{
        "F1" => %PaperForge.Reference{
          object_id: 3,
          generation: 0
        },
        "F2" => %PaperForge.Reference{
          object_id: 7,
          generation: 0
        }
      }

  Duplicate font keys are ignored.
  """
  @spec resource_dictionary(
          t(),
          [atom()]
        ) :: map()
  def resource_dictionary(
        %__MODULE__{} = registry,
        font_keys
      )
      when is_list(font_keys) do
    font_keys
    |> Enum.uniq()
    |> Enum.map(fn font_key ->
      font =
        fetch!(
          registry,
          font_key
        )

      {
        font.resource_name,
        font.reference
      }
    end)
    |> Map.new()
  end

  @doc """
  Returns the resource name that will be assigned to the next new font.
  """
  @spec next_resource_name(t()) :: binary()
  def next_resource_name(%__MODULE__{} = registry) do
    "F#{registry.next_resource_id}"
  end

  defp create_font(
         %__MODULE__{} = registry,
         font_key,
         %Reference{} = reference
       ) do
    definition =
      Builtin.fetch!(font_key)

    resource_name =
      next_resource_name(registry)

    font =
      Font.new(
        definition,
        resource_name,
        reference
      )

    updated_registry =
      %{
        registry
        | fonts:
            Map.put(
              registry.fonts,
              font_key,
              font
            ),
          next_resource_id: registry.next_resource_id + 1
      }

    {
      updated_registry,
      font
    }
  end

  defp resource_number(%Font{
         resource_name: resource_name
       }) do
    resource_name
    |> String.trim_leading("F")
    |> String.to_integer()
  end
end
