alias PaperForge.Page

output_path =
  Path.expand(
    "../tmp/paper_forge_new_features_with_image.pdf",
    __DIR__
  )

image_path =
  Path.expand(
    "../assets/sample_converted.jpg",
    __DIR__
  )

File.mkdir_p!(
  Path.dirname(output_path)
)

unless File.exists?(image_path) do
  raise """
  No se encontro la imagen de prueba.

  Coloca un archivo aqui:
  #{image_path}
  """
end

document =
  PaperForge.new(
    compress: true
  )
  |> PaperForge.metadata(
       title: "PaperForge - New features with image",
       author: "Manuel Garcia",
       subject: "Compression, margins, coordinates, text and JPEG images",
       keywords: [
         "Elixir",
         "PDF",
         "PaperForge",
         "JPEG"
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
         content_width = Page.content_width(page)
         left = Page.content_left(page)

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
              "Testing new features",
              y: 92,
              width: content_width,
              align: :center,
              font: :helvetica_oblique,
              size: 13
            )
         |> Page.line(
              x1: left,
              y1: 115,
              x2: left + content_width,
              y2: 115,
              width: 1
            )
         |> Page.text_box(
              """
              This document tests PaperForge new features.

              This page uses top-left coordinates, page margins,
              automatic font registration, text measurement,
              wrapping and compressed content streams.

              Below there is a JPEG image rendered as a PDF XObject.
              """,
              y: 145,
              width: content_width,
              font: :helvetica,
              size: 12,
              line_height: 17,
              align: :left
            )
         |> Page.rectangle(
              x: left,
              y: 285,
              width: content_width,
              height: 210,
              line_width: 1
            )
         |> Page.text(
              "JPEG image test",
              y: 305,
              width: content_width,
              align: :center,
              font: :times_bold,
              size: 18
            )
         |> Page.image(
              image_path,
              x: left + 110,
              y: 335,
              width: 250
            )
         |> Page.text(
              "Rendered from file path, preserving aspect ratio",
              y: 555,
              width: content_width,
              align: :center,
              font: :courier,
              size: 10
            )
         |> Page.text_box(
              """
              The same JPEG can be reused multiple times and should be
              registered only once internally through the image registry.
              """,
              y: 610,
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
         content_width = Page.content_width(page)
         left = Page.content_left(page)
         bottom = Page.content_bottom(page)
         top = Page.content_top(page)

         page
         |> Page.text(
              "Second page - landscape orientation",
              x: left,
              y: top,
              width: content_width,
              align: :center,
              font: :helvetica_bold,
              size: 22
            )
         |> Page.text_box(
              """
              This page uses the traditional PDF coordinate system:
              the origin is at the bottom-left corner.

              The same JPEG image is drawn again below.
              If image deduplication works correctly, the image data
              should be embedded only once in the document.
              """,
              x: left,
              y: top - 55,
              width: content_width,
              font: :helvetica,
              size: 12,
              line_height: 18
            )
         |> Page.image(
              image_path,
              x: left + 40,
              y: 180,
              width: 180
            )
         |> Page.image(
              image_path,
              x: left + 280,
              y: 180,
              width: 120
            )
         |> Page.rectangle(
              x: left,
              y: bottom,
              width: content_width,
              height: 90,
              line_width: 1
            )
         |> Page.text(
              "Bottom area calculated from page margins",
              x: left,
              y: bottom + 38,
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
PDF generated successfully.

Path:
#{output_path}

Image used:
#{image_path}

Size:
#{byte_size(pdf)} bytes

Compression detected:
#{if String.contains?(pdf, "/FlateDecode"), do: "yes", else: "no"}

Pages:
2
""")