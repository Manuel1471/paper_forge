defmodule PaperForge.Coordinates do
  @moduledoc """
  Helpers for converting between PDF coordinate systems.

  PDF uses the bottom-left corner as its native origin. PaperForge can
  also expose a top-left origin, which is often easier for document
  layout.

  Supported origins:

  - `:bottom_left`
  - `:top_left`
  """

  @type origin ::
          :bottom_left
          | :top_left

  @doc """
  Converts a point Y coordinate into PDF coordinates.

  For `:bottom_left`, the value is returned unchanged.

  For `:top_left`, the value is measured from the top edge of the page.

  ## Examples

      PaperForge.Coordinates.point_y(
        842,
        72,
        :top_left
      )
      #=> 770

      PaperForge.Coordinates.point_y(
        842,
        72,
        :bottom_left
      )
      #=> 72
  """
  @spec point_y(
          number(),
          number(),
          origin()
        ) :: number()
  def point_y(
        page_height,
        y,
        :bottom_left
      ) do
    validate_page_height!(page_height)
    validate_coordinate!(:y, y)

    y
  end

  def point_y(
        page_height,
        y,
        :top_left
      ) do
    validate_page_height!(page_height)
    validate_coordinate!(:y, y)

    page_height - y
  end

  def point_y(
        page_height,
        y,
        origin
      ) do
    validate_page_height!(page_height)
    validate_coordinate!(:y, y)
    validate_origin!(origin)
  end

  @doc """
  Converts the Y coordinate of a rectangular element into PDF
  coordinates.

  This should be used for elements whose Y coordinate represents the
  top or bottom edge of a box, such as:

  - rectangles;
  - images;
  - text boxes;
  - other elements with a known height.

  When the origin is `:top_left`, the element height is subtracted so
  the box appears below the provided Y coordinate.

  ## Examples

      PaperForge.Coordinates.box_y(
        842,
        72,
        100,
        :top_left
      )
      #=> 670

      PaperForge.Coordinates.box_y(
        842,
        72,
        100,
        :bottom_left
      )
      #=> 72
  """
  @spec box_y(
          number(),
          number(),
          number(),
          origin()
        ) :: number()
  def box_y(
        page_height,
        y,
        height,
        :bottom_left
      ) do
    validate_page_height!(page_height)
    validate_coordinate!(:y, y)
    validate_dimension!(:height, height)

    y
  end

  def box_y(
        page_height,
        y,
        height,
        :top_left
      ) do
    validate_page_height!(page_height)
    validate_coordinate!(:y, y)
    validate_dimension!(:height, height)

    page_height - y - height
  end

  def box_y(
        page_height,
        y,
        height,
        origin
      ) do
    validate_page_height!(page_height)
    validate_coordinate!(:y, y)
    validate_dimension!(:height, height)
    validate_origin!(origin)
  end

  @doc """
  Converts two Y coordinates used by a line.

  ## Example

      PaperForge.Coordinates.line_y(
        842,
        72,
        120,
        :top_left
      )
      #=> {770, 722}
  """
  @spec line_y(
          number(),
          number(),
          number(),
          origin()
        ) :: {number(), number()}
  def line_y(
        page_height,
        y1,
        y2,
        origin
      ) do
    {
      point_y(
        page_height,
        y1,
        origin
      ),
      point_y(
        page_height,
        y2,
        origin
      )
    }
  end

  @doc """
  Returns whether the provided origin is supported.
  """
  @spec valid_origin?(term()) :: boolean()
  def valid_origin?(origin) do
    origin in [
      :bottom_left,
      :top_left
    ]
  end

  @doc """
  Validates and returns an origin.

  Raises `ArgumentError` for unsupported values.
  """
  @spec validate_origin!(term()) :: origin()
  def validate_origin!(origin)
      when origin in [
             :bottom_left,
             :top_left
           ] do
    origin
  end

  def validate_origin!(origin) do
    raise ArgumentError,
          "unsupported coordinate origin #{inspect(origin)}. " <>
            "Expected :bottom_left or :top_left"
  end

  defp validate_page_height!(page_height)
       when is_number(page_height) and
              page_height > 0 do
    :ok
  end

  defp validate_page_height!(page_height) do
    raise ArgumentError,
          "page height must be greater than zero, received: " <>
            inspect(page_height)
  end

  defp validate_coordinate!(
         _name,
         coordinate
       )
       when is_number(coordinate) do
    :ok
  end

  defp validate_coordinate!(
         name,
         coordinate
       ) do
    raise ArgumentError,
          "#{name} must be a number, received: " <>
            inspect(coordinate)
  end

  defp validate_dimension!(
         _name,
         dimension
       )
       when is_number(dimension) and
              dimension >= 0 do
    :ok
  end

  defp validate_dimension!(
         name,
         dimension
       ) do
    raise ArgumentError,
          "#{name} must be a non-negative number, received: " <>
            inspect(dimension)
  end
end
