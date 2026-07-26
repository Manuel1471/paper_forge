alias PaperForge.Page

document =
  PaperForge.new()
  |> PaperForge.add_page(fn page ->
    Page.text(
      page,
      "Page 1",
      x: 72,
      y: 750,
      size: 32
    )
  end)
  |> PaperForge.add_page(fn page ->
    Page.text(
      page,
      "Page 2",
      x: 72,
      y: 750,
      size: 32
    )
  end)

File.mkdir_p!("tmp")
PaperForge.write!(document, "tmp/two_pages.pdf")