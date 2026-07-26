defmodule PaperForge.Image do
  @moduledoc """
  Represents an image registered inside a PDF document.

  PaperForge supports JPEG and PNG images embedded as PDF image
  XObjects.

  A registered image contains:

  - its content hash;
  - original width and height;
  - color space;
  - bits per component;
  - raw image data;
  - internal PDF resource name;
  - indirect object reference.

  ## Example

      %PaperForge.Image{
        hash: <<...>>,
        format: :png,
        width: 1200,
        height: 800,
        color_space: :device_rgb,
        bits_per_component: 8,
        data: image_binary,
        resource_name: "Im1",
        reference: %PaperForge.Reference{
          object_id: 8,
          generation: 0
        }
      }
  """

  alias PaperForge.Reference

  @enforce_keys [
    :hash,
    :format,
    :width,
    :height,
    :color_space,
    :bits_per_component,
    :data,
    :resource_name,
    :reference
  ]

  defstruct [
    :hash,
    :format,
    :width,
    :height,
    :color_space,
    :bits_per_component,
    :data,
    :resource_name,
    :reference
  ]

  @type format ::
          :jpeg
          | :png

  @type color_space ::
          :device_gray
          | :device_rgb
          | :device_cmyk

  @type t :: %__MODULE__{
          hash: binary(),
          format: format(),
          width: pos_integer(),
          height: pos_integer(),
          color_space: color_space(),
          bits_per_component: pos_integer(),
          data: binary(),
          resource_name: binary(),
          reference: Reference.t()
        }

  @doc """
  Creates a registered image.

  The metadata map must contain:

  - `:width`
  - `:height`
  - `:color_space`
  - `:bits_per_component`
  """
  @spec new(
          binary(),
          format(),
          map(),
          binary(),
          binary(),
          Reference.t()
        ) :: t()
  def new(
        hash,
        format,
        metadata,
        data,
        resource_name,
        %Reference{} = reference
      )
      when is_binary(hash) and
             is_map(metadata) and
             is_binary(data) and
             is_binary(resource_name) and
             byte_size(resource_name) > 0 do
    validate_format!(format)

    width =
      metadata
      |> Map.fetch!(:width)
      |> validate_dimension!(:width)

    height =
      metadata
      |> Map.fetch!(:height)
      |> validate_dimension!(:height)

    color_space =
      metadata
      |> Map.fetch!(:color_space)
      |> validate_color_space!()

    bits_per_component =
      metadata
      |> Map.fetch!(:bits_per_component)
      |> validate_bits_per_component!()

    %__MODULE__{
      hash: hash,
      format: format,
      width: width,
      height: height,
      color_space: color_space,
      bits_per_component: bits_per_component,
      data: data,
      resource_name: resource_name,
      reference: reference
    }
  end

  @doc """
  Calculates the display size while preserving aspect ratio when only
  one dimension is provided.

  Supported combinations:

  - neither width nor height: use original dimensions;
  - only width: calculate height;
  - only height: calculate width;
  - both width and height: use both values directly.

  ## Examples

      PaperForge.Image.display_size(
        image,
        width: 200
      )

      PaperForge.Image.display_size(
        image,
        height: 100
      )
  """
  @spec display_size(t(), keyword()) :: {number(), number()}
  def display_size(
        %__MODULE__{} = image,
        options \\ []
      )
      when is_list(options) do
    width =
      Keyword.get(
        options,
        :width
      )

    height =
      Keyword.get(
        options,
        :height
      )

    case {
      width,
      height
    } do
      {nil, nil} ->
        {
          image.width,
          image.height
        }

      {width, nil}
      when is_number(width) and
             width > 0 ->
        {
          width,
          width *
            image.height /
            image.width
        }

      {nil, height}
      when is_number(height) and
             height > 0 ->
        {
          height *
            image.width /
            image.height,
          height
        }

      {width, height}
      when is_number(width) and
             width > 0 and
             is_number(height) and
             height > 0 ->
        {
          width,
          height
        }

      _ ->
        raise ArgumentError,
              "image width and height must be positive numbers"
    end
  end

  @doc """
  Returns the PDF name associated with the image color space.
  """
  @spec pdf_color_space(t() | color_space()) :: {:name, binary()}
  def pdf_color_space(%__MODULE__{
        color_space: color_space
      }) do
    pdf_color_space(color_space)
  end

  def pdf_color_space(:device_gray) do
    {
      :name,
      "DeviceGray"
    }
  end

  def pdf_color_space(:device_rgb) do
    {
      :name,
      "DeviceRGB"
    }
  end

  def pdf_color_space(:device_cmyk) do
    {
      :name,
      "DeviceCMYK"
    }
  end

  @doc """
  Returns a SHA-256 hash for image binary data.

  This hash can be used by `PaperForge.ImageRegistry` to avoid storing
  the same image more than once.
  """
  @spec hash(binary()) :: binary()
  def hash(data) when is_binary(data) do
    :crypto.hash(
      :sha256,
      data
    )
  end

  @doc """
  Returns a hexadecimal representation of an image hash.

  This is mainly useful for debugging and tests.
  """
  @spec hash_hex(t() | binary()) :: binary()
  def hash_hex(%__MODULE__{
        hash: hash
      }) do
    hash_hex(hash)
  end

  def hash_hex(hash)
      when is_binary(hash) do
    Base.encode16(
      hash,
      case: :lower
    )
  end

  defp validate_format!(:jpeg) do
    :jpeg
  end

  defp validate_format!(:png) do
    :png
  end

  defp validate_format!(format) do
    raise ArgumentError,
          "unsupported image format #{inspect(format)}. Expected :jpeg or :png"
  end

  defp validate_dimension!(
         value,
         _name
       )
       when is_integer(value) and
              value > 0 do
    value
  end

  defp validate_dimension!(
         value,
         name
       ) do
    raise ArgumentError,
          "#{name} must be a positive integer, received: " <>
            inspect(value)
  end

  defp validate_color_space!(color_space)
       when color_space in [
              :device_gray,
              :device_rgb,
              :device_cmyk
            ] do
    color_space
  end

  defp validate_color_space!(color_space) do
    raise ArgumentError,
          "unsupported image color space #{inspect(color_space)}"
  end

  defp validate_bits_per_component!(value)
       when is_integer(value) and
              value > 0 and
              value <= 16 do
    value
  end

  defp validate_bits_per_component!(value) do
    raise ArgumentError,
          "bits per component must be an integer between 1 and 16, " <>
            "received: #{inspect(value)}"
  end
end
