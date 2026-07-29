defmodule PaperForge.Barcode do
  @moduledoc "Interleaved 2 of 5 barcode encoding for numeric identifiers."
  @patterns %{
    ?0 => [1, 1, 3, 3, 1],
    ?1 => [3, 1, 1, 1, 3],
    ?2 => [1, 3, 1, 1, 3],
    ?3 => [3, 3, 1, 1, 1],
    ?4 => [1, 1, 3, 1, 3],
    ?5 => [3, 1, 3, 1, 1],
    ?6 => [1, 3, 3, 1, 1],
    ?7 => [1, 1, 1, 3, 3],
    ?8 => [3, 1, 1, 3, 1],
    ?9 => [1, 3, 1, 3, 1]
  }

  def interleaved_2_of_5(data) when is_binary(data) do
    unless data =~ ~r/^\d+$/, do: raise(ArgumentError, "Interleaved 2 of 5 accepts digits only")
    data = if rem(byte_size(data), 2) == 1, do: "0" <> data, else: data

    body =
      data
      |> String.to_charlist()
      |> Enum.chunk_every(2)
      |> Enum.flat_map(fn [a, b] ->
        Enum.zip(Map.fetch!(@patterns, a), Map.fetch!(@patterns, b))
        |> Enum.flat_map(fn {bar, gap} -> [{true, bar}, {false, gap}] end)
      end)

    [{true, 1}, {false, 1}, {true, 1}, {false, 1}] ++ body ++ [{true, 3}, {false, 1}, {true, 1}]
  end
end
