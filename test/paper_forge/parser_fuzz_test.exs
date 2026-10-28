defmodule PaperForge.ParserFuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias PaperForge.{Interoperability, Page}

  @moduletag :fuzz

  setup_all do
    assert {:ok, _document} = Interoperability.parse_pdf(valid_pdf())
    :ok
  end

  property "mutated PDFs are accepted or rejected without creating input atoms" do
    seeds = [
      valid_pdf(),
      File.read!(Path.expand("../fixtures/interoperability/object-streams.pdf", __DIR__)),
      File.read!(Path.expand("../fixtures/interoperability/incremental.pdf", __DIR__))
    ]

    check all(
            baseline <- member_of(seeds),
            mutations <- list_of(mutation(), min_length: 1, max_length: 12),
            suffix <- string(:alphanumeric, min_length: 12, max_length: 32),
            max_runs: 80
          ) do
      marker = "parser_fuzz_#{suffix}_#{System.unique_integer([:positive])}"
      refute_existing_atom(marker)

      pdf =
        mutations
        |> Enum.reduce(baseline, &mutate/2)
        |> Kernel.<>("\n% #{marker}\n")

      result =
        Interoperability.parse_pdf(pdf,
          timeout: 1000,
          max_file_size: 200_000,
          max_objects: 500,
          max_recursion_depth: 24,
          max_uncompressed_stream_bytes: 32_000
        )

      assert match?({:ok, _}, result) or match?({:error, _}, result)
      refute_existing_atom(marker)
    end
  end

  test "mutation sequences remain valid after repeated truncation" do
    mutations = [:truncate, :truncate, :truncate, :truncate, :truncate, :truncate, :flip]

    mutated = Enum.reduce(mutations, valid_pdf(), &mutate/2)

    assert is_binary(mutated)
    assert byte_size(mutated) > 0
  end

  defp valid_pdf do
    PaperForge.new(compress: false)
    |> PaperForge.add_page(fn page -> Page.text(page, "Parser fuzz seed", x: 40, y: 40) end)
    |> PaperForge.to_binary()
  end

  defp mutation do
    one_of([
      constant(:truncate),
      constant(:append),
      tuple({constant(:flip), integer(0..100_000)}),
      constant(:nest)
    ])
  end

  defp mutate(:truncate, pdf), do: binary_part(pdf, 0, div(byte_size(pdf), 2))
  defp mutate(:append, pdf), do: pdf <> "\n999 0 obj\n<< /Fuzz (value) >>\nendobj\n"

  defp mutate(:flip, pdf), do: mutate({:flip, 17}, pdf)
  defp mutate({:flip, _}, <<>>), do: <<0>>

  defp mutate({:flip, offset}, pdf) do
    position = rem(offset, byte_size(pdf))
    <<head::binary-size(^position), byte, tail::binary>> = pdf
    head <> <<Bitwise.bxor(byte, 0x5A)>> <> tail
  end

  defp mutate(:nest, pdf), do: pdf <> String.duplicate("[", 4)

  defp refute_existing_atom(value) do
    assert_raise ArgumentError, fn -> String.to_existing_atom(value) end
  end
end
