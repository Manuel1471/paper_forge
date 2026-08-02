defmodule PaperForge.AnnotationTest do
  use ExUnit.Case, async: true

  alias PaperForge.Page

  test "emits common review annotations, attachments, and conversation replies" do
    document =
      PaperForge.new(compress: false)
      |> PaperForge.add_page(fn page ->
        page
        |> Page.note("Review this", x: 40, y: 40, width: 20, height: 20)
        |> Page.highlight("Important", x: 40, y: 80, width: 100, height: 16)
        |> Page.underline("Source", x: 40, y: 110, width: 100, height: 16)
        |> Page.strikeout("Removed", x: 40, y: 140, width: 100, height: 16)
        |> Page.stamp("Approved", x: 40, y: 170, width: 90, height: 28, name: "Approved")
        |> Page.annotation(:square, x: 40, y: 220, width: 80, height: 50, contents: "Area")
        |> Page.annotation(:ink,
          x: 40,
          y: 290,
          width: 100,
          height: 40,
          points: [[40, 300, 70, 315, 120, 300]]
        )
        |> Page.annotation(:file_attachment,
          x: 40,
          y: 350,
          width: 20,
          height: 20,
          filename: "evidence.txt",
          data: "review evidence",
          contents: "Evidence"
        )
      end)

    pdf = PaperForge.to_binary(document)

    for subtype <- ~w(Text Highlight Underline StrikeOut Stamp Square Ink FileAttachment) do
      assert pdf =~ "/Subtype /#{subtype}"
    end

    assert pdf =~ "/EmbeddedFile"
    assert pdf =~ "evidence.txt"
  end
end
