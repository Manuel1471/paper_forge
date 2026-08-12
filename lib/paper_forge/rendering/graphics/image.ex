defmodule PaperForge.Graphics.Image do
  @moduledoc """
  Builds PDF drawing commands for image XObjects.

  Images are drawn with the PDF `cm` transformation matrix followed by
  the `Do` operator.

  ## Example output

      q
      180 0 0 90 72 600 cm
      /Im1 Do
      Q
  """

  alias PaperForge.Serializer

  @type option ::
          {:x, number()}
          | {:y, number()}
          | {:width, number()}
          | {:height, number()}
          | {:clip, {number(), number(), number(), number()}}
          | {:matrix, {number(), number(), number(), number(), number(), number()}}

  @doc """
  Generates the PDF commands required to draw an image.

  Required arguments:

  - `resource_name` — internal PDF resource name such as `"Im1"`
  - `:x`
  - `:y`
  - `:width`
  - `:height`

  ## Example

      PaperForge.Graphics.Image.command(
        "Im1",
        x: 72,
        y: 600,
        width: 180,
        height: 90
      )
  """
  @spec command(binary(), [option()]) :: iodata()
  def command(
        resource_name,
        options
      )
      when is_binary(resource_name) and is_list(options) do
    validate_resource_name!(resource_name)
    validate_options!(options)

    x =
      Keyword.fetch!(
        options,
        :x
      )

    y =
      Keyword.fetch!(
        options,
        :y
      )

    width =
      Keyword.fetch!(
        options,
        :width
      )

    height =
      Keyword.fetch!(
        options,
        :height
      )

    clip =
      case Keyword.get(options, :clip) do
        nil ->
          []

        {clip_x, clip_y, clip_width, clip_height} ->
          [
            Serializer.encode(clip_x),
            " ",
            Serializer.encode(clip_y),
            " ",
            Serializer.encode(clip_width),
            " ",
            Serializer.encode(clip_height),
            " re W n\n"
          ]
      end

    matrix =
      Keyword.get(options, :matrix, {width, 0, 0, height, x, y})

    [
      "q\n",
      clip,
      encode_matrix(matrix),
      " cm\n",
      "/",
      resource_name,
      " Do\n",
      "Q"
    ]
  end

  defp validate_options!(options) do
    validate_required_option!(
      options,
      :x
    )

    validate_required_option!(
      options,
      :y
    )

    validate_required_option!(
      options,
      :width
    )

    validate_required_option!(
      options,
      :height
    )

    validate_coordinate!(
      :x,
      Keyword.fetch!(options, :x)
    )

    validate_coordinate!(
      :y,
      Keyword.fetch!(options, :y)
    )

    validate_dimension!(
      :width,
      Keyword.fetch!(options, :width)
    )

    validate_dimension!(
      :height,
      Keyword.fetch!(options, :height)
    )

    validate_clip!(Keyword.get(options, :clip))
    validate_matrix!(Keyword.get(options, :matrix))
  end

  defp encode_matrix(matrix) do
    matrix
    |> Tuple.to_list()
    |> Enum.map_intersperse(" ", &Serializer.encode/1)
  end

  defp validate_clip!(nil), do: :ok

  defp validate_clip!({x, y, width, height})
       when is_number(x) and is_number(y) and is_number(width) and width > 0 and
              is_number(height) and height > 0,
       do: :ok

  defp validate_clip!(clip) do
    raise ArgumentError,
          "image clip must be {x, y, width, height} with positive dimensions, received: " <>
            inspect(clip)
  end

  defp validate_matrix!(nil), do: :ok

  defp validate_matrix!({a, b, c, d, e, f})
       when is_number(a) and is_number(b) and is_number(c) and is_number(d) and is_number(e) and
              is_number(f),
       do: :ok

  defp validate_matrix!(matrix) do
    raise ArgumentError,
          "image matrix must contain six numbers, received: #{inspect(matrix)}"
  end

  defp validate_required_option!(
         options,
         option
       ) do
    unless Keyword.has_key?(
             options,
             option
           ) do
      raise ArgumentError,
            "missing required image option #{inspect(option)}"
    end
  end

  defp validate_coordinate!(
         _name,
         value
       )
       when is_number(value) do
    :ok
  end

  defp validate_coordinate!(
         name,
         value
       ) do
    raise ArgumentError,
          "#{name} must be a number, received: #{inspect(value)}"
  end

  defp validate_dimension!(
         _name,
         value
       )
       when is_number(value) and value > 0 do
    :ok
  end

  defp validate_dimension!(
         name,
         value
       ) do
    raise ArgumentError,
          "#{name} must be greater than zero, received: " <>
            inspect(value)
  end

  defp validate_resource_name!(resource_name)
       when is_binary(resource_name) and
              byte_size(resource_name) > 0 do
    :ok
  end

  defp validate_resource_name!(resource_name) do
    raise ArgumentError,
          "image resource name must be a non-empty string, received: " <>
            inspect(resource_name)
  end
end
