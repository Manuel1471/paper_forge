alias PaperForge.FontRegistry
alias PaperForge.Page
alias PaperForge.TextMetrics

font_path = "test/fixtures/fonts/SFNSMono.ttf"
font_data = File.read!(font_path)
sample_text = "Informacion del usuario — ¿listo? — Привет — Ω — € © ™"

measure = fn label, function ->
  {time_us, result} = :timer.tc(function)

  IO.inspect(
    %{
      benchmark: label,
      time_ms: Float.round(time_us / 1000, 2)
    },
    label: "PaperForge TrueType"
  )

  result
end

document =
  measure.("register TrueType font", fn ->
    PaperForge.new()
    |> PaperForge.register_font(:sfmono, data: font_data)
  end)

{:ok, font} = FontRegistry.fetch(document.font_registry, :sfmono)

measure.("measure 10,000 strings", fn ->
  for _index <- 1..10_000 do
    TextMetrics.width(
      sample_text,
      font: :sfmono,
      font_instance: font,
      size: 12
    )
  end
end)

measure.("render 1,000 lines", fn ->
  PaperForge.new()
  |> PaperForge.register_font(:sfmono, data: font_data)
  |> PaperForge.add_page(fn page ->
    Enum.reduce(1..1_000, page, fn index, current_page ->
      y =
        780 - rem(index, 60) * 12

      Page.text(
        current_page,
        "#{index}. #{sample_text}",
        x: 36,
        y: y,
        font: :sfmono,
        size: 9
      )
    end)
  end)
  |> PaperForge.to_binary()
end)

measure.("generate multilingual PDF", fn ->
  PaperForge.new()
  |> PaperForge.register_font(:sfmono, data: font_data)
  |> PaperForge.add_page(
    [
      size: :a4,
      origin: :top_left,
      margins: 72
    ],
    fn page ->
      page
      |> Page.text(
        sample_text,
        y: 72,
        width: Page.content_width(page),
        align: :center,
        font: :sfmono,
        size: 18
      )
      |> Page.text_box(
        Enum.join(List.duplicate(sample_text, 12), "\n"),
        y: 120,
        width: Page.content_width(page),
        font: :sfmono,
        size: 11,
        line_height: 15
      )
    end
  )
  |> PaperForge.to_binary()
end)

IO.puts("Physical TrueType table subsetting benchmark: pending until /FontFile2 reconstruction is implemented.")
