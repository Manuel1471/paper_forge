defmodule PaperForge.PageCompilerTest do
  use ExUnit.Case, async: true

  alias PaperForge.Document
  alias PaperForge.ImageRegistry
  alias PaperForge.Page
  alias PaperForge.PageCompiler

  test "compiles bottom-left coordinates without flipping y values" do
    page =
      Page.new(size: {200, 300}, origin: :bottom_left)
      |> Page.text("Text", x: 10, y: 20)
      |> Page.line(x1: 10, y1: 20, x2: 30, y2: 40)
      |> Page.rectangle(x: 10, y: 20, width: 30, height: 40)
      |> Page.circle(x: 10, y: 20, radius: 5)

    {_document, content, resources} =
      PageCompiler.compile(
        page,
        Document.new()
      )

    assert content =~ "1 0 0 1 10 20 Tm"
    assert content =~ "10 20 m\n30 40 l"
    assert content =~ "10 20 30 40 re"
    assert content =~ "10 25 m"
    assert Map.has_key?(resources.fonts, "F1")
  end

  test "compiles top-left coordinates by flipping y values" do
    page =
      Page.new(size: {200, 300}, origin: :top_left)
      |> Page.text("Text", x: 10, y: 20)
      |> Page.line(x1: 10, y1: 20, x2: 30, y2: 40)
      |> Page.rectangle(x: 10, y: 20, width: 30, height: 40)
      |> Page.circle(x: 10, y: 20, radius: 5)

    {_document, content, _resources} =
      PageCompiler.compile(
        page,
        Document.new()
      )

    assert content =~ "1 0 0 1 10 280 Tm"
    assert content =~ "10 280 m\n30 260 l"
    assert content =~ "10 240 30 40 re"
    assert content =~ "10 285 m"
  end

  test "compiles text boxes using transformed coordinates" do
    page =
      Page.new(size: {200, 300}, origin: :top_left)
      |> Page.text_box(
        "first second third",
        x: 10,
        y: 20,
        width: 36,
        size: 10,
        line_height: 12
      )

    {_document, content, _resources} =
      PageCompiler.compile(
        page,
        Document.new()
      )

    assert content =~ "1 0 0 1 10 280 Tm"
    assert content =~ "1 0 0 1 10 268 Tm"
  end

  test "compiles images into XObject resources and preserves aspect ratio" do
    page =
      Page.new(size: {200, 300}, origin: :top_left)
      |> Page.image(
        jpeg(100, 50, 3),
        x: 10,
        y: 20,
        width: 40
      )

    {document, content, resources} =
      PageCompiler.compile(
        page,
        Document.new()
      )

    assert content =~ "40 0 0 20 10 260 cm"
    assert content =~ "/Im1 Do"
    assert Map.has_key?(resources.xobjects, "Im1")
    assert ImageRegistry.count(document.image_registry) == 1
  end

  test "supports contain and cover image fitting with focal positioning" do
    contain_page =
      Page.new(size: {200, 300}, origin: :top_left)
      |> Page.image(jpeg(100, 50, 3),
        x: 10,
        y: 20,
        width: 40,
        height: 40,
        fit: :contain
      )

    {_document, contain_content, _resources} =
      PageCompiler.compile(contain_page, Document.new())

    assert contain_content =~ "40 0 0 20 10 250 cm"

    cover_page =
      Page.new(size: {200, 300}, origin: :top_left)
      |> Page.image(jpeg(100, 50, 3),
        x: 10,
        y: 20,
        width: 40,
        height: 40,
        fit: :cover,
        focal_point: {0.5, 0.5}
      )

    {_document, cover_content, _resources} =
      PageCompiler.compile(cover_page, Document.new())

    assert cover_content =~ "10 240 40 40 re W n"
    assert cover_content =~ "80 0 0 40 -10 240 cm"
  end

  test "compiles PNG images into XObject resources" do
    page =
      Page.new(size: {200, 300}, origin: :top_left)
      |> Page.image(
        png(20, 10, 8, 2, <<0, 255, 0, 0, 0, 255, 0>>),
        x: 10,
        y: 20,
        width: 40
      )

    {document, content, resources} =
      PageCompiler.compile(
        page,
        Document.new()
      )

    assert content =~ "40 0 0 20 10 260 cm"
    assert content =~ "/Im1 Do"
    assert Map.has_key?(resources.xobjects, "Im1")
    assert ImageRegistry.count(document.image_registry) == 1
  end

  test "rejects missing image paths" do
    page =
      Page.new()
      |> Page.image(
        "/path/that/does/not/exist.jpg",
        x: 10,
        y: 10,
        width: 40
      )

    assert_raise ArgumentError, ~r/existing image file path/, fn ->
      PageCompiler.compile(
        page,
        Document.new()
      )
    end
  end

  defp jpeg(width, height, components) do
    component_data =
      for component <- 1..components, into: <<>> do
        <<component, 0x11, 0>>
      end

    segment_length =
      8 + components * 3

    <<
      0xFF,
      0xD8,
      0xFF,
      0xC0,
      segment_length::16-big,
      8,
      height::16-big,
      width::16-big,
      components,
      component_data::binary,
      0xFF,
      0xD9
    >>
  end

  defp png(width, height, bit_depth, color_type, scanlines) do
    ihdr =
      <<
        width::32-big,
        height::32-big,
        bit_depth,
        color_type,
        0,
        0,
        0
      >>

    [
      <<137, 80, 78, 71, 13, 10, 26, 10>>,
      chunk("IHDR", ihdr),
      chunk("IDAT", :zlib.compress(scanlines)),
      chunk("IEND", "")
    ]
    |> IO.iodata_to_binary()
  end

  defp chunk(type, data) do
    [
      <<byte_size(data)::32-big>>,
      type,
      data,
      <<0::32-big>>
    ]
  end
end
