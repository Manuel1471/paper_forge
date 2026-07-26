defmodule PaperForge.Object do
  @moduledoc """
  Represents an indirect PDF object.

  An object such as:

      3 0 obj
      << /Type /Page >>
      endobj

  has an object ID, generation number and value.
  """

  @enforce_keys [:id, :value]
  defstruct id: nil,
            generation: 0,
            value: nil

  @type t :: %__MODULE__{
          id: pos_integer(),
          generation: non_neg_integer(),
          value: term()
        }

  @spec new(pos_integer(), term()) :: t()
  def new(id, value) when is_integer(id) and id > 0 do
    %__MODULE__{
      id: id,
      generation: 0,
      value: value
    }
  end
end
