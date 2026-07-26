alias PaperForge.Page

document =
  PaperForge.new()
  |> PaperForge.add_page(fn page ->
    page
    |> Page.text(
         "Hello from PaperForge",
         x: 72,
         y: 750,
         size: 24
       )
    |> Page.text(
         "This PDF was generated directly with Elixir.",
         x: 72,
         y: 710,
         size: 12
       )
  end)

File.mkdir_p!("tmp")
PaperForge.write!(document, "tmp/hello.pdf")

IO.puts("Generated tmp/hello.pdf")