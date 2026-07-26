defmodule PaperForge.Reference do
  @moduledoc """
  Represents an indirect reference to a PDF object.

  A reference such as `3 0 R` points to the indirect object
  identified by object number 3 and generation 0.
  """

  @enforce_keys [:object_id]
  defstruct object_id: nil, generation: 0

  @type t :: %__MODULE__{
          object_id: pos_integer(),
          generation: non_neg_integer()
        }

  @spec new(pos_integer()) :: t()
  def new(object_id) when is_integer(object_id) and object_id > 0 do
    %__MODULE__{object_id: object_id}
  end

  @spec new(pos_integer(), non_neg_integer()) :: t()
  def new(object_id, generation)
      when is_integer(object_id) and object_id > 0 and
             is_integer(generation) and generation >= 0 do
    %__MODULE__{
      object_id: object_id,
      generation: generation
    }
  end
end
