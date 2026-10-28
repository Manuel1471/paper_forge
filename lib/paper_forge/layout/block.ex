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
      id:
        case Keyword.fetch(options, :id) do
          {:ok, id} -> id
          :error -> stable_id(type, content, options)
        end,
      type: type,
      content: content,
      options: Keyword.drop(options, [:id, :children]),
      children: Keyword.get(options, :children, [])
    }
  end

  defp stable_id(type, content, options) do
    base = {type, content, Keyword.drop(options, [:children])}

    identity =
      case Keyword.get(options, :children, []) do
        [] -> base
        children -> {base, Enum.map(children, & &1.id)}
      end

    data = :erlang.term_to_binary(identity)

    hash =
      :crypto.hash(:sha256, data)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "#{type}-#{hash}"
  end
end
