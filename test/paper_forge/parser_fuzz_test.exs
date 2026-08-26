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
    baseline = valid_pdf()

    check all(
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
          max_file_size: 200_000,
          max_objects: 500,
          max_recursion_depth: 24,
          max_uncompressed_stream_bytes: 32_000
        )

      assert match?({:ok, _}, result) or match?({:error, _}, result)
      refute_existing_atom(marker)
    end
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
      constant(:flip),
      constant(:nest)
    ])
  end

  defp mutate(:truncate, pdf), do: binary_part(pdf, 0, div(byte_size(pdf), 2))
  defp mutate(:append, pdf), do: pdf <> "\n999 0 obj\n<< /Fuzz (value) >>\nendobj\n"

  defp mutate(:flip, <<>>), do: <<0>>

  defp mutate(:flip, pdf) do
    position = rem(byte_size(pdf), 17)
    <<head::binary-size(^position), byte, tail::binary>> = pdf
    head <> <<Bitwise.bxor(byte, 0x5A)>> <> tail
  end

  defp mutate(:nest, pdf), do: pdf <> String.duplicate("[", 4)

  defp refute_existing_atom(value) do
    assert_raise ArgumentError, fn -> String.to_existing_atom(value) end
  end
end
