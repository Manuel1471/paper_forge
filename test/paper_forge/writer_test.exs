defmodule PaperForge.WriterTest do
  use ExUnit.Case, async: true

  alias PaperForge.Page
  alias PaperForge.Writer

  test "generates a complete PDF binary" do
    document =
      PaperForge.new()
      |> PaperForge.add_page(fn page ->
        Page.text(page, "Hello", x: 72, y: 750)
      end)

    pdf = Writer.to_binary(document)

    assert String.starts_with?(pdf, "%PDF-1.7")
    assert pdf =~ "/Type /Catalog"
    assert pdf =~ "/Type /Pages"
    assert pdf =~ "/Type /Page"
    assert pdf =~ "(Hello) Tj"
    assert pdf =~ "xref"
    assert pdf =~ "trailer"
    assert pdf =~ "startxref"
    assert String.ends_with?(pdf, "%%EOF\n")
  end
end
