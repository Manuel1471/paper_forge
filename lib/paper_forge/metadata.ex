defmodule PaperForge.Metadata do
  @moduledoc """
  Represents basic PDF document metadata.
  """

  defstruct title: nil,
            author: nil,
            subject: nil,
            keywords: [],
            creator: "PaperForge",
            producer: "PaperForge"

  @type t :: %__MODULE__{
          title: binary() | nil,
          author: binary() | nil,
          subject: binary() | nil,
          keywords: [binary()],
          creator: binary() | nil,
          producer: binary() | nil
        }

  @spec new(keyword()) :: t()
  def new(options \\ []) do
    struct!(__MODULE__, options)
  end

  @spec to_dictionary(t()) :: map()
  def to_dictionary(%__MODULE__{} = metadata) do
    %{}
    |> put_optional("Title", metadata.title)
    |> put_optional("Author", metadata.author)
    |> put_optional("Subject", metadata.subject)
    |> put_optional("Creator", metadata.creator)
    |> put_optional("Producer", metadata.producer)
    |> put_keywords(metadata.keywords)
  end

  defp put_optional(dictionary, _key, nil), do: dictionary
  defp put_optional(dictionary, key, value), do: Map.put(dictionary, key, value)

  defp put_keywords(dictionary, []), do: dictionary

  defp put_keywords(dictionary, keywords) do
    Map.put(dictionary, "Keywords", Enum.join(keywords, ", "))
  end
end
