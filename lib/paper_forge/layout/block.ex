defmodule PaperForge.Layout.Block do
  @moduledoc """
  Common block representation used by the unified layout engine.
  """

  defstruct [
    :id,
    :type,
    :content,
    options: [],
    children: []
  ]

  @type t :: %__MODULE__{
          id: binary(),
          type: atom(),
          content: term(),
          options: keyword(),
          children: [t()]
        }

  @spec new(atom(), term(), keyword()) :: t()
  def new(type, content, options \\ []) do
    %__MODULE__{
      id: Keyword.get(options, :id, stable_id(type, content, options)),
      type: type,
      content: content,
      options: Keyword.delete(options, :id),
      children: Keyword.get(options, :children, [])
    }
  end

  defp stable_id(type, content, options) do
    data =
      :erlang.term_to_binary({
        type,
        content,
        Keyword.drop(options, [:children])
      })

    hash =
      :crypto.hash(:sha256, data)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "#{type}-#{hash}"
  end
end
