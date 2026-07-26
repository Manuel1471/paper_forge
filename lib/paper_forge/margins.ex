defmodule PaperForge.Margins do
  @moduledoc """
  Represents page margins.

  Margins can be created from:

  - one number, applied to every side;
  - a keyword list with individual values;
  - an existing `PaperForge.Margins` struct.

  ## Examples

      PaperForge.Margins.new(72)

      PaperForge.Margins.new(
        top: 40,
        right: 50,
        bottom: 40,
        left: 50
      )
  """

  defstruct top: 0,
            right: 0,
            bottom: 0,
            left: 0

  @type t :: %__MODULE__{
          top: number(),
          right: number(),
          bottom: number(),
          left: number()
        }

  @doc """
  Creates margins with zero on every side.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Creates margins from one value, a keyword list, or an existing
  margins struct.

  A numeric value is applied to all four sides.

  Missing keyword values default to zero.
  """
  @spec new(number() | keyword() | t()) :: t()
  def new(%__MODULE__{} = margins) do
    margins
  end

  def new(value)
      when is_number(value) and value >= 0 do
    %__MODULE__{
      top: value,
      right: value,
      bottom: value,
      left: value
    }
  end

  def new(options)
      when is_list(options) do
    validate_keyword_list!(options)

    %__MODULE__{
      top:
        options
        |> Keyword.get(:top, 0)
        |> validate_margin!(:top),
      right:
        options
        |> Keyword.get(:right, 0)
        |> validate_margin!(:right),
      bottom:
        options
        |> Keyword.get(:bottom, 0)
        |> validate_margin!(:bottom),
      left:
        options
        |> Keyword.get(:left, 0)
        |> validate_margin!(:left)
    }
  end

  def new(value) do
    raise ArgumentError,
          "margins must be a non-negative number, keyword list, or " <>
            "PaperForge.Margins struct, received: #{inspect(value)}"
  end

  @doc """
  Returns the total horizontal margin.

  This is the sum of the left and right margins.
  """
  @spec horizontal(t()) :: number()
  def horizontal(%__MODULE__{} = margins) do
    margins.left + margins.right
  end

  @doc """
  Returns the total vertical margin.

  This is the sum of the top and bottom margins.
  """
  @spec vertical(t()) :: number()
  def vertical(%__MODULE__{} = margins) do
    margins.top + margins.bottom
  end

  @doc """
  Returns the content width for a page.

  Raises when the margins consume all available page width.
  """
  @spec content_width(t(), number()) :: number()
  def content_width(
        %__MODULE__{} = margins,
        page_width
      ) do
    validate_page_dimension!(
      :page_width,
      page_width
    )

    width =
      page_width -
        horizontal(margins)

    if width > 0 do
      width
    else
      raise ArgumentError,
            "horizontal margins must leave a positive content width"
    end
  end

  @doc """
  Returns the content height for a page.

  Raises when the margins consume all available page height.
  """
  @spec content_height(t(), number()) :: number()
  def content_height(
        %__MODULE__{} = margins,
        page_height
      ) do
    validate_page_dimension!(
      :page_height,
      page_height
    )

    height =
      page_height -
        vertical(margins)

    if height > 0 do
      height
    else
      raise ArgumentError,
            "vertical margins must leave a positive content height"
    end
  end

  @doc """
  Validates that margins fit inside a page.

  Returns the margins unchanged when valid.
  """
  @spec validate_page!(t(), number(), number()) :: t()
  def validate_page!(
        %__MODULE__{} = margins,
        page_width,
        page_height
      ) do
    content_width(
      margins,
      page_width
    )

    content_height(
      margins,
      page_height
    )

    margins
  end

  @doc """
  Converts margins to a keyword list.
  """
  @spec to_keyword(t()) :: keyword()
  def to_keyword(%__MODULE__{} = margins) do
    [
      top: margins.top,
      right: margins.right,
      bottom: margins.bottom,
      left: margins.left
    ]
  end

  defp validate_keyword_list!(options) do
    supported_keys =
      MapSet.new([
        :top,
        :right,
        :bottom,
        :left
      ])

    invalid_keys =
      options
      |> Keyword.keys()
      |> Enum.reject(
        &MapSet.member?(
          supported_keys,
          &1
        )
      )

    case invalid_keys do
      [] ->
        :ok

      keys ->
        raise ArgumentError,
              "unsupported margin options: " <>
                Enum.map_join(
                  keys,
                  ", ",
                  &inspect/1
                )
    end
  end

  defp validate_margin!(
         value,
         _name
       )
       when is_number(value) and value >= 0 do
    value
  end

  defp validate_margin!(
         value,
         name
       ) do
    raise ArgumentError,
          "#{name} margin must be a non-negative number, received: " <>
            inspect(value)
  end

  defp validate_page_dimension!(
         _name,
         value
       )
       when is_number(value) and value > 0 do
    :ok
  end

  defp validate_page_dimension!(
         name,
         value
       ) do
    raise ArgumentError,
          "#{name} must be greater than zero, received: " <>
            inspect(value)
  end
end
