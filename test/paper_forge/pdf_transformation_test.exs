defmodule PaperForge.PDF.TransformationTest do
  use ExUnit.Case, async: true
  alias PaperForge.{Document, Interoperability, Page}
  alias PaperForge.PDF.Graph

  defp document do
    Enum.reduce(1..4, PaperForge.new(compress: false), fn n, document ->
      PaperForge.add_page(document, &Page.text(&1, "Page #{n}", x: 20, y: 20))
    end)
    |> PaperForge.metadata(title: "Original", author: "Author")
  end

  @tag :tmp_dir
  test "existing PDF can be transformed and reopened", %{tmp_dir: dir} do
    input = Path.join(dir, "input.pdf")
    output = Path.join(dir, "output.pdf")
    PaperForge.write!(document(), input)
    original = PaperForge.open!(input)

    edited =
      original
      |> PaperForge.delete_pages(2..3)
      |> PaperForge.rotate_pages([2], 90)
      |> PaperForge.add_watermark("CONFIDENTIAL")
      |> PaperForge.update_metadata(title: "Reviewed")

    assert :ok = PaperForge.write!(edited, output)
    reopened = PaperForge.open!(output)
    assert PaperForge.page_count(reopened) == 2
    assert PaperForge.metadata(reopened)["Title"] == "Reviewed"
    assert PaperForge.metadata(reopened)["Author"] == "Author"
    assert {:ok, [_, last]} = Graph.pages(reopened)
    assert last.dictionary["Rotate"] == 90
    assert PaperForge.page_count(original) == 4
    assert {:ok, report} = PaperForge.analyze(reopened)
    assert report.broken_references == []
  end

  test "watermarks preserve shared indirect resources and avoid name collisions" do
    original = document()
    {:ok, [first | _]} = Graph.pages(original)

    resources =
      Map.update!(
        first.dictionary["Resources"],
        "Font",
        &Map.put(&1, "PFWatermark", hd(Map.values(&1)))
      )

    {original, resources_ref} = Document.add_object(original, resources)

    original =
      Document.update_object(original, first.reference, &Map.put(&1, "Resources", resources_ref))

    edited = PaperForge.add_watermark(original, "Reviewed")
    assert {:ok, [page | _]} = Graph.pages(edited)
    assert page.dictionary["Resources"]["Font"]["PFWatermark"] == resources["Font"]["PFWatermark"]
    assert page.dictionary["Resources"]["Font"]["PFWatermark_"]
    assert edited.objects[resources_ref.object_id] == original.objects[resources_ref.object_id]
    assert {:ok, _} = edited |> PaperForge.to_binary() |> Interoperability.parse_pdf()
  end

  test "extraction, reordering, merge and normalization preserve valid graphs" do
    document = document()
    {:ok, pages} = Graph.pages(document)
    reordered = PaperForge.reorder_pages(document, [4, 3, 2, 1])
    {:ok, reversed} = Graph.pages(reordered)
    assert Enum.map(reversed, & &1.reference) == Enum.reverse(Enum.map(pages, & &1.reference))
    assert {:ok, extracted} = PaperForge.extract_pages(document, [2, 4])
    assert PaperForge.page_count(extracted) == 2
    assert {:ok, merged} = PaperForge.merge([extracted, extracted])
    assert PaperForge.page_count(merged) == 4
    normalized = document |> PaperForge.delete_pages([1, 2]) |> PaperForge.normalize()
    assert {:ok, report} = PaperForge.analyze(normalized)
    assert report.orphaned_objects == []
    assert report.broken_references == []
    assert {:ok, _} = normalized |> PaperForge.to_binary() |> Interoperability.parse_pdf()
    assert_raise ArgumentError, fn -> PaperForge.rotate_pages(document, [0], 90) end
    assert_raise ArgumentError, fn -> PaperForge.rotate_pages(document, [1], 45) end
    assert_raise ArgumentError, fn -> PaperForge.reorder_pages(document, [1, 2]) end
  end
end
