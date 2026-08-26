defmodule PaperForge.LimitError do
  @moduledoc """
  Raised when a configured document serialization limit is exceeded.

  Limits bound object count, source stream bytes, and nested PDF value depth
  before the writer allocates the complete PDF binary.
  """

  defexception [:limit, :actual, :maximum, :message]

  @type t :: %__MODULE__{
          limit: atom(),
          actual: non_neg_integer(),
          maximum: pos_integer(),
          message: binary()
        }

  @impl true
  def exception(options) do
    limit = Keyword.fetch!(options, :limit)
    actual = Keyword.fetch!(options, :actual)
    maximum = Keyword.fetch!(options, :maximum)

    %__MODULE__{
      limit: limit,
      actual: actual,
      maximum: maximum,
      message: "#{limit} exceeded: #{actual} is greater than #{maximum}"
    }
  end
end
