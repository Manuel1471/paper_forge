alias PaperForge.Color
alias PaperForge.Page

document =
  PaperForge.new()
  |> PaperForge.metadata(
       title: "PaperForge Graphics",
       author: "Manuel Garcia",
       subject: "PaperForge 0.1.0 graphics example",
       keywords: [
         "Elixir",
         "PDF",
         "PaperForge"
       ],
       creator: "PaperForge 0.1.0"
     )
  |> PaperForge.add_page(fn page ->
    page
    |> Page.text(
         "PaperForge 0.1.0",
         x: 72,
         y: 760,
         size: 28,
         color: Color.rgb255(35, 60, 120)
       )
    |> Page.line(
         x1: 72,
         y1: 740,
         x2: 520,
         y2: 740,
         width: 2,
         color: Color.rgb255(35, 60, 120)
       )
    |> Page.rectangle(
         x: 72,
         y: 580,
         width: 220,
         height: 110,
         fill: true,
         stroke: true,
         fill_color: Color.rgb255(235, 240, 250),
         stroke_color: Color.rgb255(35, 60, 120),
         line_width: 2
       )
    |> Page.text(
         "Pure Elixir PDF",
         x: 95,
         y: 630,
         size: 18,
         color: Color.rgb255(35, 60, 120)
       )
    |> Page.circle(
         x: 400,
         y: 635,
         radius: 55,
         fill: true,
         stroke: true,
         fill_color: Color.rgb255(245, 180, 70),
         stroke_color: Color.rgb255(120, 70, 20),
         line_width: 2
       )
  end)
  |> PaperForge.add_page(
       [
         size: :letter,
         orientation: :landscape
       ],
       fn page ->
         page
         |> Page.text(
              "Landscape Letter Page",
              x: 72,
              y: 500,
              size: 32,
              color: Color.rgb255(90, 40, 120)
            )
         |> Page.rectangle(
              x: 70,
              y: 430,
              width: 400,
              height: 40,
              fill: true,
              stroke: false,
              fill_color: Color.rgb255(230, 215, 245)
            )
       end
     )

File.mkdir_p!("tmp")

PaperForge.write!(
  document,
  "tmp/paper_forge_0_1.pdf"
)

IO.puts(
  "Generated tmp/paper_forge_0_1.pdf"
)