defmodule PaperForge.Stream do
  @moduledoc """
  Represents a PDF stream composed of a dictionary and binary data.
  """

  defstruct dictionary: %{}, data: ""

  @type t :: %__MODULE__{
          dictionary: map(),
          data: iodata()
        }

  @spec new(iodata()) :: t()
  def new(data) do
    %__MODULE__{data: data}
  end

  @spec new(map(), iodata()) :: t()
  def new(dictionary, data) when is_map(dictionary) do
    %__MODULE__{
      dictionary: dictionary,
      data: data
    }
  end
end
