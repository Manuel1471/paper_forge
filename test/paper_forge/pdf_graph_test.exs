defmodule PaperForge.PDF.GraphTest do
  use ExUnit.Case, async: true
  alias PaperForge.{Interoperability, Reference}
  alias PaperForge.PDF.Graph
  alias PaperForge.Test.PDFFixture, as: Fixture

  def nested do
    Fixture.classic([
      {1, 0,
       "<< /Type /Pages /Kids [4 0 R] /Count 2 /MediaBox [0 0 200 300] /Resources 7 0 R /Rotate 90 >>"},
      {2, 0, "<< /Type /Catalog /Pages 1 0 R >>"},
      {3, 0, "<< /Type /Page /Parent 4 0 R >>"},
      {4, 0, "<< /Type /Pages /Parent 1 0 R /Kids [3 0 R 5 0 R] /Count 2 >>"},
      {5, 0, "<< /Type /Page /Parent 4 0 R /Rotate 180 >>"},
      {7, 0, "<< /Font << /F1 8 0 R >> >>"},
      {8, 0, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"}
    ])
  end

  test "walks nested page trees and materializes inherited values for import" do
    assert {:ok, document} = Interoperability.parse_pdf(nested())
    assert {:ok, [first, second]} = Graph.pages(document)
    assert first.dictionary["MediaBox"] == [0, 0, 200, 300]
    assert first.dictionary["Rotate"] == 90
    assert second.dictionary["Rotate"] == 180
    assert {:ok, _} = PaperForge.validate(document)
    assert {:ok, selected} = Interoperability.import_pages(document, [2])
    assert {:ok, [page]} = Graph.pages(selected)
    assert page.dictionary["Rotate"] == 180

    assert {:ok, %{"Font" => %{"F1" => %Reference{}}}} =
             Graph.resolve(selected, page.dictionary["Resources"])

    assert {:ok, _} = selected |> PaperForge.to_binary() |> Interoperability.parse_pdf()

    assert Enum.count(selected.objects, fn {_, o} ->
             is_map(o.value) && not is_struct(o.value) && o.value["Type"] == {:name, "Page"}
           end) == 1
  end

  test "import does not silently remap missing or stale resource references" do
    assert {:ok, document} = Interoperability.parse_pdf(nested())

    for reference <- [Reference.new(8, 1), Reference.new(999)] do
      broken =
        PaperForge.Document.update_object(
          document,
          Reference.new(7),
          &Map.put(&1, "Font", %{"F1" => reference})
        )

      assert {:error, {:broken_reference, _, _}} = Interoperability.import_pages(broken, [1])
      assert {:error, {:broken_reference, _, _}} = Interoperability.compose([broken])
    end

    document = %{document | root_reference: Reference.new(2, 1)}
    assert {:error, issues} = PaperForge.validate(document)
    assert Enum.any?(issues, &(&1.code == :generation_mismatch))
  end

  test "document fetch and update honor reference generations" do
    document = PaperForge.new()
    stale = %{document.root_reference | generation: 1}
    assert :error = PaperForge.Document.fetch_object(document, stale)
    assert_raise KeyError, fn -> PaperForge.Document.fetch_object!(document, stale) end
    assert_raise KeyError, fn -> PaperForge.Document.update_object(document, stale, & &1) end
  end

  test "transforms pages and roots with nonzero generations" do
    pdf =
      Fixture.classic(
        [
          {1, 2, "<< /Type /Pages /Kids [3 7 R] /Count 1 >>"},
          {2, 3, "<< /Type /Catalog /Pages 1 2 R >>"},
          {3, 7, "<< /Type /Page /Parent 1 2 R /MediaBox [0 0 200 300] >>"}
        ],
        %{"Root" => Reference.new(2, 3)}
      )

    assert {:ok, document} = Interoperability.parse_pdf(pdf)
    document = PaperForge.rotate_pages(document, [1], 90)
    assert {:ok, reopened} = document |> PaperForge.to_binary() |> Interoperability.parse_pdf()
    assert reopened.objects[3].generation == 7
    assert reopened.objects[3].value["Rotate"] == 90
  end

  test "rejects cycles and generation mismatches" do
    assert {:ok, document} = Interoperability.parse_pdf(nested())
    assert {:error, {:broken_reference, 3, 1}} = Graph.resolve(document, Reference.new(3, 1))

    document =
      PaperForge.Document.update_object(
        document,
        Reference.new(4),
        &Map.put(&1, "Kids", [Reference.new(1)])
      )

    assert {:error, :cyclic_or_duplicate_page_tree} = Graph.pages(document)
    assert {:error, _} = PaperForge.validate(document)
  end
end
