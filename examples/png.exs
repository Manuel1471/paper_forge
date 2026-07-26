alias PaperForge.Page

output_path =
  Path.expand(
    "../tmp/png_example.pdf",
    __DIR__
  )

png_path =
  Path.expand(
    "../assets/sample.png",
    __DIR__
  )

File.mkdir_p!(
  Path.dirname(output_path)
)

unless File.regular?(png_path) do
  raise """
  Missing PNG test file:

  #{png_path}

  Place a valid PNG file at:

      assets/sample.png
  """
end

png_data =
  File.read!(
    png_path
  )

png_signature =
  <<
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10
  >>

unless String.starts_with?(
         png_data,
         png_signature
       ) do
  raise """
  The file exists, but it is not a real PNG image:

  #{png_path}

  Check it with:

      file assets/sample.png
  """
end

document =
  PaperForge.new(
    compress: true,
    pdf_version: "1.7"
  )
  |> PaperForge.metadata(
       title: "PaperForge PNG example",
       author: "Manuel Garcia",
       subject: "Full-color PNG rendering and deduplication test",
       keywords: [
         "PaperForge",
         "PNG",
         "Elixir",
         "PDF"
       ],
       creation_date: DateTime.utc_now()
     )
  |> PaperForge.add_page(
       [
         size: :a4,
         origin: :top_left,
         margins: 45
       ],
       fn page ->
         content_width =
           Page.content_width(page)

         left =
           Page.content_left(page)

         page
         |> Page.text(
              "PaperForge PNG support",
              y: 48,
              width: content_width,
              align: :center,
              font: :helvetica_bold,
              size: 24
            )
         |> Page.text(
              "Full-color PNG loaded from a file path",
              y: 88,
              width: content_width,
              align: :center,
              font: :helvetica,
              size: 13
            )
         |> Page.rectangle(
              x: left,
              y: 115,
              width: content_width,
              height: 380,
              line_width: 1
            )
         |> Page.image(
              png_path,
              x: left + 130,
              y: 140,
              width: 240
            )
         |> Page.text(
              "Aspect ratio preserved using width only",
              y: 525,
              width: content_width,
              align: :center,
              font: :courier,
              size: 10
            )
         |> Page.text_box(
              """
              The image above was loaded using its file path.

              PaperForge detects the PNG signature, reads its dimensions and
              embeds it as a PDF image XObject using Flate compression.
              """,
              y: 575,
              width: content_width,
              font: :times_roman,
              size: 11,
              line_height: 16,
              align: :left
            )
         |> Page.rectangle(
              x: left,
              y: 690,
              width: content_width,
              height: 80,
              line_width: 1
            )
         |> Page.text(
              "PNG color image rendered successfully",
              y: 720,
              width: content_width,
              align: :center,
              font: :helvetica_bold,
              size: 13
            )
       end
     )
  |> PaperForge.add_page(
       [
         size: :letter,
         orientation: :landscape,
         origin: :bottom_left,
         margins: 40
       ],
       fn page ->
         content_width =
           Page.content_width(page)

         left =
           Page.content_left(page)

         top =
           Page.content_top(page)

         bottom =
           Page.content_bottom(page)

         page
         |> Page.text(
              "PNG scaling and deduplication",
              x: left,
              y: top,
              width: content_width,
              align: :center,
              font: :helvetica_bold,
              size: 22
            )
         |> Page.text_box(
              """
              The same PNG binary is rendered three times at different sizes.

              PaperForge should embed the image data only once and reuse the
              same image resource for every drawing operation.
              """,
              x: left,
              y: top - 45,
              width: content_width,
              font: :helvetica,
              size: 11,
              line_height: 16
            )
         |> Page.image(
              png_data,
              x: left + 20,
              y: 175,
              width: 200
            )
         |> Page.image(
              png_data,
              x: left + 275,
              y: 175,
              width: 140
            )
         |> Page.image(
              png_data,
              x: left + 480,
              y: 175,
              height: 170
            )
         |> Page.rectangle(
              x: left,
              y: bottom,
              width: content_width,
              height: 75,
              line_width: 1
            )
         |> Page.text(
              "One PNG resource reused in multiple render operations",
              x: left,
              y: bottom + 30,
              width: content_width,
              align: :center,
              font: :courier_bold,
              size: 12
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

registered_images =
  map_size(
    document.image_registry.images
  )

IO.puts("""
PNG PDF generated successfully.

Output:
#{output_path}

PNG source:
#{png_path}

Registered images:
#{registered_images}

PDF size:
#{byte_size(pdf)} bytes

FlateDecode present:
#{String.contains?(pdf, "/FlateDecode")}

Image XObject present:
#{String.contains?(pdf, "/Subtype /Image")}

PNG predictor present:
#{String.contains?(pdf, "/Predictor")}

DeviceRGB present:
#{String.contains?(pdf, "/DeviceRGB")}
""")