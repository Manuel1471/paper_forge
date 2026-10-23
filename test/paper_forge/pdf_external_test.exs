defmodule PaperForge.PDF.ExternalTest do
  use ExUnit.Case, async: true
  alias PaperForge.PDF.{Filters, Graph}

  @fixtures Path.expand("../fixtures/interoperability", __DIR__)

  for {filename, type, revisions} <- [
        {"classic.pdf", :table, 0},
        {"object-streams.pdf", :stream, 0},
        {"incremental.pdf", :mixed, 1},
        {"linearized.pdf", :table, 0},
        {"aes256.pdf", :stream, 0}
      ] do
    @tag :tmp_dir
    test "opens and rewrites independent #{filename}", %{tmp_dir: dir} do
      document = PaperForge.open!(Path.join(@fixtures, unquote(filename)), password: "reader")
      assert PaperForge.page_count(document) == 2
      assert {:ok, report} = PaperForge.analyze(document)
      assert report.cross_reference_type == unquote(type)
      assert report.incremental_revisions == unquote(revisions)
      assert report.broken_references == []
      assert {:ok, [page | _]} = Graph.pages(document)
      assert {:ok, stream} = Graph.resolve(document, page.dictionary["Contents"])
      assert {:ok, contents} = Filters.decode(stream)
      assert contents =~ "Independent page 1"
      output = Path.join(dir, "output.pdf")

      document
      |> PaperForge.rotate_pages([1], 90)
      |> PaperForge.add_watermark("REVIEWED")
      |> PaperForge.write!(output)

      assert PaperForge.page_count(PaperForge.open!(output)) == 2
    end
  end

  test "unsupported encryption is explicit and incorrect password is rejected" do
    assert {:error, {:unsupported_encryption, %{"R" => 4}}} =
             PaperForge.open(Path.join(@fixtures, "unsupported-aes128.pdf"), password: "reader")

    assert {:error, :invalid_password} =
             PaperForge.open(Path.join(@fixtures, "aes256.pdf"), password: "wrong")
  end
end
