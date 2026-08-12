defmodule PaperForge.PageResources do
  @moduledoc """
  Represents the resources used by a PDF page.

  A page can reference resources such as:

  - fonts;
  - images and other XObjects;
  - graphics states;
  - color spaces;
  - patterns.

  PaperForge currently uses fonts and image XObjects directly, while the
  remaining resource groups are included to keep the structure extensible.
  """

  alias PaperForge.Font
  alias PaperForge.Image
  alias PaperForge.Reference

  defstruct fonts: %{},
            xobjects: %{},
            graphics_states: %{},
            color_spaces: %{},
            patterns: %{}

  @type resource_dictionary :: %{
          optional(binary()) => Reference.t()
        }

  @type t :: %__MODULE__{
          fonts: resource_dictionary(),
          xobjects: resource_dictionary(),
          graphics_states: resource_dictionary(),
          color_spaces: resource_dictionary(),
          patterns: resource_dictionary()
        }

  @doc """
  Creates an empty page resource collection.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Adds a registered font to the page resources.

  The font is stored using its internal PDF resource name, such as
  `"F1"` or `"F2"`.

  Adding the same resource again replaces the existing reference.
  """
  @spec put_font(t(), Font.t()) :: t()
  def put_font(
        %__MODULE__{} = resources,
        %Font{} = font
      ) do
    put_font(
      resources,
      font.resource_name,
      font.reference
    )
  end

  @doc """
  Adds a font reference directly.

  ## Example

      resources =
        PaperForge.PageResources.put_font(
          resources,
          "F1",
          reference
        )
  """
  @spec put_font(t(), binary(), Reference.t()) :: t()
  def put_font(
        %__MODULE__{} = resources,
        resource_name,
        %Reference{} = reference
      ) do
    validate_resource_name!(resource_name)

    %{
      resources
      | fonts:
          Map.put(
            resources.fonts,
            resource_name,
            reference
          )
    }
  end

  @doc """
  Adds a registered image as a page XObject.

  Images are stored using internal names such as `"Im1"`.
  """
  @spec put_image(t(), Image.t()) :: t()
  def put_image(
        %__MODULE__{} = resources,
        %Image{} = image
      ) do
    put_xobject(
      resources,
      image.resource_name,
      image.reference
    )
  end

  @doc """
  Adds an XObject reference directly.
  """
  @spec put_xobject(t(), binary(), Reference.t()) :: t()
  def put_xobject(
        %__MODULE__{} = resources,
        resource_name,
        %Reference{} = reference
      ) do
    validate_resource_name!(resource_name)

    %{
      resources
      | xobjects:
          Map.put(
            resources.xobjects,
            resource_name,
            reference
          )
    }
  end

  @doc """
  Adds an external graphics state resource.
  """
  @spec put_graphics_state(t(), binary(), Reference.t()) :: t()
  def put_graphics_state(
        %__MODULE__{} = resources,
        resource_name,
        %Reference{} = reference
      ) do
    validate_resource_name!(resource_name)

    %{
      resources
      | graphics_states:
          Map.put(
            resources.graphics_states,
            resource_name,
            reference
          )
    }
  end

  @doc """
  Adds a color-space resource.
  """
  @spec put_color_space(t(), binary(), Reference.t()) :: t()
  def put_color_space(
        %__MODULE__{} = resources,
        resource_name,
        %Reference{} = reference
      ) do
    validate_resource_name!(resource_name)

    %{
      resources
      | color_spaces:
          Map.put(
            resources.color_spaces,
            resource_name,
            reference
          )
    }
  end

  @doc """
  Adds a pattern resource.
  """
  @spec put_pattern(t(), binary(), Reference.t()) :: t()
  def put_pattern(
        %__MODULE__{} = resources,
        resource_name,
        %Reference{} = reference
      ) do
    validate_resource_name!(resource_name)

    %{
      resources
      | patterns:
          Map.put(
            resources.patterns,
            resource_name,
            reference
          )
    }
  end

  @doc """
  Returns whether the page has any resources.
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = resources) do
    map_size(resources.fonts) == 0 and
      map_size(resources.xobjects) == 0 and
      map_size(resources.graphics_states) == 0 and
      map_size(resources.color_spaces) == 0 and
      map_size(resources.patterns) == 0
  end

  @doc """
  Merges two page resource collections.

  Resources from the second argument replace resources with the same
  name in the first.
  """
  @spec merge(t(), t()) :: t()
  def merge(
        %__MODULE__{} = left,
        %__MODULE__{} = right
      ) do
    %__MODULE__{
      fonts:
        Map.merge(
          left.fonts,
          right.fonts
        ),
      xobjects:
        Map.merge(
          left.xobjects,
          right.xobjects
        ),
      graphics_states:
        Map.merge(
          left.graphics_states,
          right.graphics_states
        ),
      color_spaces:
        Map.merge(
          left.color_spaces,
          right.color_spaces
        ),
      patterns:
        Map.merge(
          left.patterns,
          right.patterns
        )
    }
  end

  @doc """
  Converts the resource collection into a PDF resource dictionary.

  Empty resource groups are omitted.

  ## Example result

      %{
        "Font" => %{
          "F1" => reference
        },
        "XObject" => %{
          "Im1" => image_reference
        }
      }
  """
  @spec to_dictionary(t()) :: map()
  def to_dictionary(%__MODULE__{} = resources) do
    %{}
    |> put_group(
      "Font",
      resources.fonts
    )
    |> put_group(
      "XObject",
      resources.xobjects
    )
    |> put_group(
      "ExtGState",
      resources.graphics_states
    )
    |> put_group(
      "ColorSpace",
      resources.color_spaces
    )
    |> put_group(
      "Pattern",
      resources.patterns
    )
  end

  defp put_group(
         dictionary,
         _name,
         group
       )
       when map_size(group) == 0 do
    dictionary
  end

  defp put_group(
         dictionary,
         name,
         group
       ) do
    Map.put(
      dictionary,
      name,
      group
    )
  end

  defp validate_resource_name!(resource_name)
       when is_binary(resource_name) and
              byte_size(resource_name) > 0 do
    :ok
  end

  defp validate_resource_name!(resource_name) do
    raise ArgumentError,
          "resource name must be a non-empty string, received: " <>
            inspect(resource_name)
  end
end
