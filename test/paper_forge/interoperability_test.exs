defmodule PaperForge.InteroperabilityTest do
  use ExUnit.Case, async: true

  alias PaperForge.{Interoperability, Page}

  test "parses, selects, composes, and inventories PaperForge PDFs" do
    first =
      PaperForge.new(compress: false)
      |> PaperForge.add_page(fn page -> Page.text(page, "First", x: 30, y: 30) end)

    second =
      PaperForge.new(compress: false)
      |> PaperForge.add_page(fn page -> Page.text(page, "Second", x: 30, y: 30) end)

    assert {:ok, parsed} = Interoperability.parse_pdf(PaperForge.to_binary(first))
    assert parsed.objects[parsed.pages_reference.object_id].value["Count"] == 1

    assert {:ok, selected} = Interoperability.import_pages(parsed, [1])
    assert selected.objects[selected.pages_reference.object_id].value["Count"] == 1

    assert {:ok, composed} = Interoperability.compose([PaperForge.to_binary(first), second])
    assert composed.objects[composed.pages_reference.object_id].value["Count"] == 2
    assert PaperForge.to_binary(composed) =~ "%PDF-1.7"

    assert %{fonts: fonts, xobjects: [], embedded_files: [], appearances: []} =
             Interoperability.resources(composed)

    assert fonts != []
  end

  test "rejects unsupported PDF sources predictably" do
    assert {:error, _reason} = Interoperability.parse_pdf("not a pdf")
    assert {:error, {:unsupported_pdf_source, :bad}} = Interoperability.import_pages(:bad)
  end

  test "applies explicit parsing resource limits before importing objects" do
    alias PaperForge.Test.PDFFixture, as: Fixture
    pdf = Fixture.classic(Fixture.objects())

    assert {:error, {:max_file_size_exceeded, 8}} =
             Interoperability.parse_pdf(pdf, max_file_size: 8)

    assert {:error, {:max_objects_exceeded, 1}} = Interoperability.parse_pdf(pdf, max_objects: 1)
    assert {:error, :invalid_parse_limits} = Interoperability.parse_pdf(pdf, max_objects: 0)
    nested = Fixture.classic(Fixture.objects() ++ [{4, 0, "[[[[0]]]]"}])

    for option <- [:max_depth, :max_recursion_depth] do
      assert {:error, {:max_depth_exceeded, 3}} =
               Interoperability.parse_pdf(nested, [{option, 3}])
    end

    stream =
      Fixture.classic(Fixture.objects() ++ [{4, 0, "<< /Length 5 >>\nstream\n12345\nendstream"}])

    for option <- [:max_stream_size, :max_uncompressed_stream_bytes] do
      assert {:error, {:max_stream_size_exceeded, 4}} =
               Interoperability.parse_pdf(stream, [{option, 4}])
    end
  end

  test "rejects zero, negative, and malformed page selections" do
    document =
      PaperForge.new()
      |> PaperForge.add_page(fn page -> Page.text(page, "First", x: 30, y: 30) end)
      |> PaperForge.add_page(fn page -> Page.text(page, "Second", x: 30, y: 30) end)

    assert {:error, :page_index_out_of_range} = Interoperability.import_pages(document, [0])
    assert {:error, :page_index_out_of_range} = Interoperability.import_pages(document, [-1])
    assert {:error, :page_index_out_of_range} = Interoperability.import_pages(document, [3])
    assert {:error, :page_index_out_of_range} = Interoperability.import_pages(document, 0..1)
    assert {:error, :invalid_page_selection} = Interoperability.import_pages(document, :first)
  end
end
