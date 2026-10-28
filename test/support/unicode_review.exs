alias PaperForge.{AcroForm, Page}

output = Path.expand("../../output/pdf/unicode-review", __DIR__)
File.mkdir_p!(output)
text = "Niñez — € “México” 日本語 🚚"
value = "Peña € “sí”"

document =
  PaperForge.new()
  |> PaperForge.register_font(:unicode,
    path: Path.expand("../fixtures/fonts/SFNSMono.ttf", __DIR__)
  )
  |> PaperForge.metadata(title: text, author: "Peña", subject: "a\u00A0b")
  |> PaperForge.add_page(fn page ->
    page
    |> Page.text("Unicode / revision 1.4", x: 40, y: 770, size: 24)
    |> Page.text("Valores actualizados y apariencias conservadas", x: 40, y: 735, size: 12)
    |> Page.bookmark(text)
    |> Page.note(text, x: 450, y: 700)
    |> Page.annotation(:stamp, x: 450, y: 650, contents: text, author: text, subject: text)
    |> Page.annotation(:file_attachment,
      x: 450,
      y: 600,
      filename: text <> ".txt",
      data: "annotation payload",
      description: text,
      mime_type: "text/plain"
    )
  end)
  |> PaperForge.attach("z.txt", "last", mime_type: "text/plain")
  |> PaperForge.attach(text <> ".txt", "document payload",
    description: text,
    mime_type: "text/plain"
  )
  |> AcroForm.add_field(1, :text, text,
    rect: [40, 650, 420, 682],
    value: "OLD VALUE",
    default: "España",
    tooltip: text
  )
  |> AcroForm.add_field(1, :text, "日本語", rect: [40, 590, 420, 622], value: "Ω Ж", font: :unicode)
  |> AcroForm.add_field(1, :combo, "país",
    rect: [40, 530, 420, 562],
    options: [["MX", "México"], ["ES", "España"]],
    value: "MX"
  )
  |> AcroForm.add_field(1, :text, "empty", rect: [40, 470, 420, 502])
  |> AcroForm.add_field(1, :checkbox, "off", rect: [40, 410, 60, 430], value: false)
  |> AcroForm.add_field(1, :checkbox, "on", rect: [90, 410, 110, 430], value: true)
  |> AcroForm.add_radio_group(
    "plan",
    [
      [page: 1, rect: [40, 350, 60, 370], value: "A"],
      [page: 1, rect: [90, 350, 110, 370], value: "B"]
    ],
    value: "B"
  )
  |> AcroForm.import_data(%{text => value, "日本語" => "Ж Ω Ω", "país" => "ES"})

PaperForge.write!(document, Path.join(output, "interactive.pdf"))
PaperForge.write!(AcroForm.flatten(document), Path.join(output, "flattened.pdf"))
IO.puts("Unicode review fixtures: #{output}")
