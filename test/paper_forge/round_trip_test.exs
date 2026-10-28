defmodule PaperForge.RoundTripTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias PaperForge.{Interoperability, Page}

  test "writer output parses into a valid document" do
    document = sample_document("Round-trip proof")

    assert {:ok, parsed} = document |> PaperForge.to_binary() |> Interoperability.parse_pdf()
    assert {:ok, report} = PaperForge.validate(parsed)
    assert report.valid?
    assert PaperForge.validate!(parsed).valid?
  end

  test "validate and validate! retain their error contract" do
    document = PaperForge.new() |> Map.put(:root_reference, nil)

    assert {:error, issues} = PaperForge.validate(document)

    assert %{code: :invalid_required_reference} =
             Enum.find(issues, &(&1.code == :invalid_required_reference))

    assert_raise PaperForge.ValidationError, fn -> PaperForge.validate!(document) end
  end

  property "text-only documents survive writer to binary to parser round trips" do
    check all(
            text <-
              string([32..126, 160..255, 0x20AC..0x20AC, 0x2022..0x2022],
                min_length: 1,
                max_length: 96
              ),
            max_runs: 30
          ) do
      document = sample_document(text)

      assert {:ok, parsed} = document |> PaperForge.to_binary() |> Interoperability.parse_pdf()
      assert {:ok, report} = PaperForge.validate(parsed)
      assert report.pages == 1
    end
  end

  defp sample_document(text) do
    PaperForge.new(compress: false)
    |> PaperForge.add_page(fn page -> Page.text(page, text, x: 40, y: 40) end)
  end
end
