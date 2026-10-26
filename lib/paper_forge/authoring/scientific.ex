defmodule PaperForge.Scientific do
  @moduledoc """
  Stateful builder for numbered equations, citations, bibliographies, and
  page-aware scientific cross-references.
  """

  alias PaperForge.Flow

  defstruct flow: nil,
            equation_count: 0,
            equation_destinations: %{},
            citations: %{},
            citation_order: []

  @type t :: %__MODULE__{
          flow: Flow.t(),
          equation_count: non_neg_integer(),
          equation_destinations: map(),
          citations: map(),
          citation_order: [binary()]
        }

  @spec new(Flow.t()) :: t()
  def new(flow \\ Flow.new()), do: %__MODULE__{flow: flow}

  @doc "Adds an automatically numbered equation and named destination."
  @spec equation(t(), PaperForge.Math.ast(), keyword()) :: t()
  def equation(%__MODULE__{} = scientific, ast, options \\ []) do
    number = scientific.equation_count + 1
    destination = Keyword.get(options, :destination, "equation-#{number}")
    label = Keyword.get(options, :label, "Equation #{number}")

    flow =
      scientific.flow
      |> Flow.heading(
        label,
        Keyword.merge(
          [level: Keyword.get(options, :level, 4), space_after: 4],
          Keyword.get(options, :heading_options, [])
        )
        |> Keyword.put(:destination, destination)
        |> Keyword.put(:bookmark, false)
      )
      |> Flow.math(ast, Keyword.delete(options, :destination))

    %{
      scientific
      | flow: flow,
        equation_count: number,
        equation_destinations: Map.put(scientific.equation_destinations, number, destination)
    }
  end

  @doc "Adds a page-aware reference such as `Equation 3, page 8`."
  @spec equation_reference(t(), pos_integer(), keyword()) :: t()
  def equation_reference(%__MODULE__{} = scientific, number, options \\ []) do
    text = Keyword.get(options, :text, "Equation #{number}, page {page}")
    destination = Map.get(scientific.equation_destinations, number, "equation-#{number}")

    %{
      scientific
      | flow: Flow.reference(scientific.flow, destination, Keyword.put(options, :text, text))
    }
  end

  @doc "Registers a bibliography entry and returns its stable citation number."
  @spec cite(t(), binary(), map() | keyword()) :: {t(), pos_integer()}
  def cite(%__MODULE__{} = scientific, key, entry) when is_binary(key) do
    case Enum.find_index(scientific.citation_order, &(&1 == key)) do
      nil ->
        order = scientific.citation_order ++ [key]

        {%{
           scientific
           | citation_order: order,
             citations: Map.put(scientific.citations, key, Map.new(entry))
         }, length(order)}

      index ->
        {scientific, index + 1}
    end
  end

  @doc "Adds the numbered bibliography section."
  @spec bibliography(t(), keyword()) :: t()
  def bibliography(%__MODULE__{} = scientific, options \\ []) do
    flow =
      Flow.heading(
        scientific.flow,
        Keyword.get(options, :title, "References"),
        Keyword.merge([level: 2], Keyword.get(options, :heading_options, []))
      )

    flow =
      scientific.citation_order
      |> Enum.with_index(1)
      |> Enum.reduce(flow, fn {key, number}, current ->
        entry = Map.fetch!(scientific.citations, key)

        Flow.paragraph(current, "#{number}. #{format_entry(entry)}",
          size: Keyword.get(options, :size, 9),
          hanging_indent: 14
        )
      end)

    %{scientific | flow: flow}
  end

  @doc "Returns the resulting Layout IR."
  @spec to_flow(t()) :: Flow.t()
  def to_flow(%__MODULE__{flow: flow}), do: flow

  defp format_entry(entry) do
    [
      entry[:author] || entry["author"],
      entry[:title] || entry["title"],
      entry[:year] || entry["year"],
      entry[:url] || entry["url"]
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(". ", &to_string/1)
  end
end
