alias PaperForge.Page

output_path =
  Path.expand(
    "../tmp/paper_forge_new_features.pdf",
    __DIR__
  )

File.mkdir_p!(
  Path.dirname(output_path)
)

document =
  PaperForge.new(
    compress: true
  )
  |> PaperForge.metadata(
       title: "PaperForge — Nuevas funcionalidades",
       author: "Manuel García",
       subject: "Prueba de compresión, márgenes, coordenadas y texto",
       keywords: [
         "Elixir",
         "PDF",
         "PaperForge",
         "Unicode"
       ],
       creator: "PaperForge example",
       producer: "PaperForge",
       creation_date: DateTime.utc_now(),
       modification_date: DateTime.utc_now()
     )
  |> PaperForge.add_page(
       [
         size: :a4,
         origin: :top_left,
         margins: [
           top: 50,
           right: 55,
           bottom: 50,
           left: 55
         ]
       ],
       fn page ->
         content_width =
           Page.content_width(page)

         page
         |> Page.text(
              "PaperForge",
              y: 55,
              width: content_width,
              align: :center,
              font: :helvetica_bold,
              size: 28
            )
         |> Page.text(
              "Prueba de las nuevas funcionalidades",
              y: 92,
              width: content_width,
              align: :center,
              font: :helvetica_oblique,
              size: 13
            )
         |> Page.line(
              x1: Page.content_left(page),
              y1: 115,
              x2: Page.content_left(page) + content_width,
              y2: 115,
              width: 1
            )
         |> Page.text_box(
              """
              Este documento prueba el nuevo sistema de PaperForge.

              La página utiliza coordenadas con origen en la esquina superior
              izquierda, márgenes independientes, fuentes registradas
              automáticamente, medición de texto, saltos de línea y streams
              comprimidos con FlateDecode.

              También contiene texto Unicode en los metadatos, como México,
              García y programación.
              """,
              y: 145,
              width: content_width,
              font: :helvetica,
              size: 12,
              line_height: 17,
              align: :left
            )
         |> Page.rectangle(
              x: Page.content_left(page),
              y: 330,
              width: content_width,
              height: 100,
              line_width: 1
            )
         |> Page.text(
              "Texto centrado dentro de una sección",
              y: 360,
              width: content_width,
              align: :center,
              font: :times_bold,
              size: 17
            )
         |> Page.text(
              "Helvetica, Times y Courier se registran bajo demanda.",
              y: 392,
              width: content_width,
              align: :center,
              font: :courier,
              size: 10
            )
         |> Page.circle(
              x: Page.content_left(page) + 60,
              y: 500,
              radius: 35,
              line_width: 2
            )
         |> Page.rectangle(
              x: Page.content_left(page) + 125,
              y: 465,
              width: 90,
              height: 70,
              line_width: 2
            )
         |> Page.line(
              x1: Page.content_left(page) + 260,
              y1: 465,
              x2: Page.content_left(page) + 360,
              y2: 535,
              width: 2
            )
         |> Page.text(
              "Círculo",
              x: Page.content_left(page) + 30,
              y: 555,
              width: 60,
              align: :center,
              font: :helvetica,
              size: 10
            )
         |> Page.text(
              "Rectángulo",
              x: Page.content_left(page) + 125,
              y: 555,
              width: 90,
              align: :center,
              font: :helvetica,
              size: 10
            )
         |> Page.text(
              "Línea",
              x: Page.content_left(page) + 280,
              y: 555,
              width: 60,
              align: :center,
              font: :helvetica,
              size: 10
            )
         |> Page.text_box(
              """
              El contenido de esta página está comprimido. Por ello, el texto
              no aparecerá directamente al buscarlo dentro del binario PDF,
              pero cualquier lector compatible debe mostrarlo normalmente.
              """,
              y: 630,
              width: content_width,
              font: :times_italic,
              size: 11,
              line_height: 15,
              align: :right
            )
       end
     )
  |> PaperForge.add_page(
       [
         size: :letter,
         orientation: :landscape,
         origin: :bottom_left,
         margins: 45
       ],
       fn page ->
         content_width =
           Page.content_width(page)

         page
         |> Page.text(
              "Segunda página — orientación horizontal",
              x: Page.content_left(page),
              y: Page.content_top(page),
              width: content_width,
              align: :center,
              font: :helvetica_bold,
              size: 22
            )
         |> Page.text_box(
              """
              Esta página utiliza el sistema tradicional de coordenadas PDF:
              el origen se encuentra en la esquina inferior izquierda.

              La primera página utilizó :top_left y esta utiliza :bottom_left.
              PaperForge transforma las coordenadas dependiendo de la
              configuración de cada página.
              """,
              x: Page.content_left(page),
              y: Page.content_top(page) - 55,
              width: content_width,
              font: :helvetica,
              size: 12,
              line_height: 18
            )
         |> Page.rectangle(
              x: Page.content_left(page),
              y: Page.content_bottom(page),
              width: content_width,
              height: 90,
              line_width: 1
            )
         |> Page.text(
              "Área inferior calculada con los márgenes de la página",
              x: Page.content_left(page),
              y: Page.content_bottom(page) + 38,
              width: content_width,
              align: :center,
              font: :courier_bold,
              size: 13
            )
       end
     )

:ok =
  PaperForge.write!(
    document,
    output_path
  )

pdf =
  File.read!(
    output_path
  )

IO.puts("""
PDF generado correctamente.

Ruta:
#{output_path}

Tamaño:
#{byte_size(pdf)} bytes

Compresión:
#{if String.contains?(pdf, "/FlateDecode"), do: "activada", else: "no detectada"}

Páginas:
2
""")