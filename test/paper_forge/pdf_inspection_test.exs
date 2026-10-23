defmodule PaperForge.PDF.InspectionTest do
  use ExUnit.Case, async: false
  alias PaperForge.Test.PDFFixture, as: Fixture

  @tag :tmp_dir
  test "opens files and inventories document features", %{tmp_dir: dir} do
    objects = [
      {1, 0, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"},
      {2, 0,
       "<< /Type /Catalog /Pages 1 0 R /AcroForm << /Fields [5 0 R] >> /Names << /EmbeddedFiles 7 0 R >> /Outlines 9 0 R /MarkInfo << /Marked true >> /StructTreeRoot 12 0 R >>"},
      {3, 0, "<< /Type /Page /Parent 1 0 R /MediaBox [0 0 200 300] /Annots [4 0 R] >>"},
      {4, 0, "<< /Type /Annot /Subtype /Text /Contents (Note) >>"},
      {5, 0, "<< /FT /Tx /T (Client) /V (Alice) >>"},
      {6, 0, "<< /Title (Agreement) /Author (Writer) >>"},
      {7, 0, "<< /Names [(terms.txt) 8 0 R] >>"},
      {8, 0, "<< /Type /Filespec /F (terms.txt) >>"},
      {9, 0, "<< /First 10 0 R /Last 10 0 R >>"},
      {10, 0, "<< /Title (Introduction) /Parent 9 0 R >>"},
      {11, 0, "<< /Type /Sig /ByteRange [0 10 20 30] /Contents <ABCD> >>"},
      {12, 0, "<< /Type /StructTreeRoot >>"},
      {13, 0, "<< /Type /Font /BaseFont /Helvetica >>"},
      {14, 0, "<< /Type /Font /BaseFont /Helvetica >>"},
      {15, 0, "<< /Broken 99 2 R >>"}
    ]

    path = Path.join(dir, "features.pdf")
    File.write!(path, Fixture.classic(objects, %{"Info" => PaperForge.Reference.new(6)}))
    assert {:ok, document} = PaperForge.open(path)
    assert PaperForge.open!(path) == document
    assert PaperForge.page_count(document) == 1
    assert PaperForge.metadata(document)["Title"] == "Agreement"
    assert [%{name: "Client"}] = PaperForge.forms(document)
    assert [%{page: 1}] = PaperForge.annotations(document)
    assert [%{name: "terms.txt"}] = PaperForge.attachments(document)
    assert [%{title: "Introduction", children: []}] = PaperForge.outlines(document)
    assert [%{verification: :not_performed}] = PaperForge.signatures(document)
    assert {:ok, report} = PaperForge.analyze(document)
    assert report.page_count == 1
    assert report.object_count == 15
    assert length(report.duplicate_resources) == 1
    assert [%{reference: %{object_id: 99, generation: 2}}] = report.broken_references
    assert report.tagged_pdf.mark_info == %{"Marked" => true}
    assert :deduplicate_resources in report.normalization_opportunities
    assert {:error, {:max_file_size_exceeded, 10}} = PaperForge.open(path, max_file_size: 10)
    assert {:error, :enoent} = PaperForge.open(path <> ".missing")

    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    Mix.Tasks.PaperForge.Inspect.run([path, "--json"])
    assert_received {:mix_shell, :info, [json]}
    assert Jason.decode!(json)["object_count"] == 15
  end

  test "analysis reports malformed feature trees without looping" do
    pdf =
      Fixture.classic(
        Fixture.objects() ++
          [{4, 0, "<< /First 5 0 R >>"}, {5, 0, "<< /Title (Loop) /Next 5 0 R >>"}]
      )

    assert {:ok, document} = PaperForge.Interoperability.parse_pdf(pdf)

    document =
      PaperForge.Document.update_object(
        document,
        document.root_reference,
        &Map.put(&1, "Outlines", PaperForge.Reference.new(4))
      )

    assert {:ok, report} = PaperForge.analyze(document)
    assert :cyclic_outline_tree in report.issues
  end
end
