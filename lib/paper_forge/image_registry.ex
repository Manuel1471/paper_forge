defmodule PaperForge.ImageRegistry do
  @moduledoc """
  Stores images registered inside a PDF document.

  Images are indexed by their content hash so the same image can be
  reused across multiple pages without being embedded more than once.

  Resource names are generated sequentially:

      Im1
      Im2
      Im3
  """

  alias PaperForge.Image

  defstruct images: %{},
            next_resource_id: 1

  @type t :: %__MODULE__{
          images: %{optional(binary()) => Image.t()},
          next_resource_id: pos_integer()
        }

  @doc """
  Creates an empty image registry.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Returns whether an image hash is already registered.
  """
  @spec registered?(t(), binary()) :: boolean()
  def registered?(
        %__MODULE__{} = registry,
        hash
      )
      when is_binary(hash) do
    Map.has_key?(
      registry.images,
      hash
    )
  end

  @doc """
  Fetches a registered image by hash.

  Returns `{:ok, image}` or `:error`.
  """
  @spec fetch(t(), binary()) ::
          {:ok, Image.t()}
          | :error
  def fetch(
        %__MODULE__{} = registry,
        hash
      )
      when is_binary(hash) do
    Map.fetch(
      registry.images,
      hash
    )
  end

  @doc """
  Fetches a registered image and raises when it does not exist.
  """
  @spec fetch!(t(), binary()) :: Image.t()
  def fetch!(
        %__MODULE__{} = registry,
        hash
      )
      when is_binary(hash) do
    case fetch(
           registry,
           hash
         ) do
      {:ok, image} ->
        image

      :error ->
        raise ArgumentError,
              "image with hash #{Base.encode16(hash, case: :lower)} " <>
                "has not been registered"
    end
  end

  @doc """
  Registers an image.

  When an image with the same hash already exists, the existing image
  and unchanged registry are returned.

  ## Example

      {registry, image} =
        PaperForge.ImageRegistry.register(
          registry,
          image
        )
  """
  @spec register(t(), Image.t()) ::
          {t(), Image.t()}
  def register(
        %__MODULE__{} = registry,
        %Image{} = image
      ) do
    case fetch(
           registry,
           image.hash
         ) do
      {:ok, registered_image} ->
        {
          registry,
          registered_image
        }

      :error ->
        updated_registry =
          %{
            registry
            | images:
                Map.put(
                  registry.images,
                  image.hash,
                  image
                ),
              next_resource_id: registry.next_resource_id + 1
          }

        {
          updated_registry,
          image
        }
    end
  end

  @doc """
  Adds an image directly to the registry.

  This is similar to `register/2`, but always replaces an existing image
  with the same hash.
  """
  @spec put(t(), Image.t()) :: t()
  def put(
        %__MODULE__{} = registry,
        %Image{} = image
      ) do
    already_registered =
      registered?(
        registry,
        image.hash
      )

    %{
      registry
      | images:
          Map.put(
            registry.images,
            image.hash,
            image
          ),
        next_resource_id:
          if already_registered do
            registry.next_resource_id
          else
            registry.next_resource_id + 1
          end
    }
  end

  @doc """
  Returns all registered images sorted by their resource number.
  """
  @spec all(t()) :: [Image.t()]
  def all(%__MODULE__{} = registry) do
    registry.images
    |> Map.values()
    |> Enum.sort_by(&resource_number/1)
  end

  @doc """
  Returns every registered image hash.
  """
  @spec hashes(t()) :: [binary()]
  def hashes(%__MODULE__{} = registry) do
    registry
    |> all()
    |> Enum.map(& &1.hash)
  end

  @doc """
  Returns the number of registered images.
  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{} = registry) do
    map_size(registry.images)
  end

  @doc """
  Returns the resource name that will be assigned to the next new image.

  ## Example

      PaperForge.ImageRegistry.next_resource_name(registry)
      #=> "Im1"
  """
  @spec next_resource_name(t()) :: binary()
  def next_resource_name(%__MODULE__{} = registry) do
    "Im#{registry.next_resource_id}"
  end

  @doc """
  Creates an `/XObject` resource dictionary for selected image hashes.

  Duplicate hashes are ignored.

  ## Example result

      %{
        "Im1" => %PaperForge.Reference{
          object_id: 8,
          generation: 0
        }
      }
  """
  @spec resource_dictionary(
          t(),
          [binary()]
        ) :: map()
  def resource_dictionary(
        %__MODULE__{} = registry,
        hashes
      )
      when is_list(hashes) do
    hashes
    |> Enum.uniq()
    |> Enum.map(fn hash ->
      image =
        fetch!(
          registry,
          hash
        )

      {
        image.resource_name,
        image.reference
      }
    end)
    |> Map.new()
  end

  defp resource_number(%Image{
         resource_name: resource_name
       }) do
    resource_name
    |> String.trim_leading("Im")
    |> String.to_integer()
  end
end
