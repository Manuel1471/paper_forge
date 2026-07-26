defmodule PaperForge.Color do
  @moduledoc """
  Represents colors used by PDF graphics operations.

  RGB components use values between 0 and 1.
  """

  @enforce_keys [:space, :components]
  defstruct [:space, :components]

  @type component :: number()

  @type t :: %__MODULE__{
          space: :rgb | :gray,
          components: [component()]
        }

  @spec rgb(number(), number(), number()) :: t()
  def rgb(red, green, blue) do
    components = [
      validate_component!(:red, red),
      validate_component!(:green, green),
      validate_component!(:blue, blue)
    ]

    %__MODULE__{
      space: :rgb,
      components: components
    }
  end

  @spec rgb255(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def rgb255(red, green, blue) do
    rgb(
      validate_byte!(:red, red) / 255,
      validate_byte!(:green, green) / 255,
      validate_byte!(:blue, blue) / 255
    )
  end

  @spec gray(number()) :: t()
  def gray(value) do
    %__MODULE__{
      space: :gray,
      components: [validate_component!(:gray, value)]
    }
  end

  @spec black() :: t()
  def black, do: gray(0)

  @spec white() :: t()
  def white, do: gray(1)

  defp validate_component!(_name, value)
       when is_number(value) and value >= 0 and value <= 1,
       do: value

  defp validate_component!(name, value) do
    raise ArgumentError,
          "#{name} must be a number between 0 and 1, received: #{inspect(value)}"
  end

  defp validate_byte!(_name, value)
       when is_integer(value) and value >= 0 and value <= 255,
       do: value

  defp validate_byte!(name, value) do
    raise ArgumentError,
          "#{name} must be an integer between 0 and 255, received: #{inspect(value)}"
  end
end
