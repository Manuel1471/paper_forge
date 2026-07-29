defmodule PaperForge.ValidationTest do
  use ExUnit.Case, async: true

  alias PaperForge.Object
  alias PaperForge.Reference
  alias PaperForge.ValidationError

  test "validates a complete document and reports its stable structure" do
    document =
      PaperForge.new()
      |> PaperForge.add_page(fn page -> PaperForge.Page.text(page, "Stable", x: 40, y: 40) end)

    assert {:ok, report} = PaperForge.validate(document)
    assert report.pages == 1
    assert report.objects >= 3
    assert report.deterministic?
  end

  test "rejects dangling references with structured issues" do
    document =
      PaperForge.new()
      |> Map.update!(:objects, fn objects ->
        Map.put(objects, 99, Object.new(99, %{"Broken" => Reference.new(10_000)}))
      end)

    assert {:error, issues} = PaperForge.validate(document)
    assert %{code: :dangling_reference, object_id: 99, reference: 10_000} in issues

    assert_raise ValidationError, ~r/dangling_reference/, fn ->
      PaperForge.to_binary(document)
    end
  end

  test "serialization is byte-for-byte deterministic" do
    document =
      PaperForge.new(compress: true)
      |> PaperForge.metadata(title: "Deterministic")
      |> PaperForge.add_page(fn page ->
        page
        |> PaperForge.Page.text("Same input, same bytes", x: 72, y: 72)
        |> PaperForge.Page.rectangle(x: 72, y: 100, width: 120, height: 30)
      end)

    first = PaperForge.to_binary(document)
    second = PaperForge.to_binary(document)

    assert first == second
    assert :crypto.hash(:sha256, first) == :crypto.hash(:sha256, second)
  end
end
