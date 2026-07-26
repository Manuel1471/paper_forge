defmodule PaperForge.DocumentTest do
  use ExUnit.Case, async: true

  alias PaperForge.Document
  alias PaperForge.ImageRegistry
  alias PaperForge.Object
  alias PaperForge.Reference
  alias PaperForge.Stream

  describe "new/1" do
    test "creates the initial PDF object graph" do
      document = Document.new()

      assert map_size(document.objects) == 2
      assert document.next_object_id == 3

      assert document.root_reference ==
               Reference.new(2)

      assert document.pages_reference ==
               Reference.new(1)

      assert document.info_reference == nil
      assert document.pdf_version == "1.7"
      assert document.compress == true
    end

    test "creates the initial pages object" do
      document = Document.new()

      assert {:ok, %Object{value: pages}} =
               Document.fetch_object(
                 document,
                 document.pages_reference
               )

      assert pages == %{
               "Type" => {:name, "Pages"},
               "Kids" => [],
               "Count" => 0
             }
    end

    test "creates the initial catalog object" do
      document = Document.new()

      assert {:ok, %Object{value: catalog}} =
               Document.fetch_object(
                 document,
                 document.root_reference
               )

      assert catalog == %{
               "Type" => {:name, "Catalog"},
               "Pages" => document.pages_reference
             }
    end

    test "starts with an empty font registry" do
      document = Document.new()

      assert PaperForge.FontRegistry.all(document.font_registry) == []
    end

    test "enables compression by default" do
      document = Document.new()

      assert document.compress
    end

    test "allows compression to be disabled" do
      document =
        Document.new(compress: false)

      refute document.compress
    end

    test "allows supported PDF versions" do
      document =
        Document.new(pdf_version: "1.4")

      assert document.pdf_version == "1.4"
    end

    test "rejects unsupported options" do
      assert_raise ArgumentError,
                   ~r/unsupported document options/,
                   fn ->
                     Document.new(unknown: true)
                   end
    end

    test "rejects invalid compression values" do
      assert_raise ArgumentError,
                   ~r/compress must be true or false/,
                   fn ->
                     Document.new(compress: :yes)
                   end
    end

    test "rejects unsupported PDF versions" do
      assert_raise ArgumentError,
                   ~r/unsupported PDF version/,
                   fn ->
                     Document.new(pdf_version: "2.0")
                   end
    end

    test "rejects non-string PDF versions" do
      assert_raise ArgumentError,
                   ~r/pdf_version must be a string/,
                   fn ->
                     Document.new(pdf_version: 1.7)
                   end
    end
  end

  describe "add_object/2" do
    test "adds an indirect object" do
      document = Document.new()

      {document, reference} =
        Document.add_object(
          document,
          %{"Example" => true}
        )

      assert reference == Reference.new(3)
      assert document.next_object_id == 4
      assert map_size(document.objects) == 3

      assert {:ok, %Object{value: value}} =
               Document.fetch_object(
                 document,
                 reference
               )

      assert value == %{
               "Example" => true
             }
    end
  end

  describe "append_page/2" do
    test "adds a page reference to the page tree" do
      document = Document.new()
      page_reference = Reference.new(10)

      document =
        Document.append_page(
          document,
          page_reference
        )

      assert {:ok, %Object{value: pages}} =
               Document.fetch_object(
                 document,
                 document.pages_reference
               )

      assert pages["Kids"] == [
               page_reference
             ]

      assert pages["Count"] == 1
    end
  end

  describe "register_jpeg/2" do
    test "registers RGB JPEG images as XObjects" do
      document = Document.new()

      {document, image} =
        Document.register_jpeg(
          document,
          jpeg(320, 240, 3)
        )

      assert image.width == 320
      assert image.height == 240
      assert image.color_space == :device_rgb
      assert image.resource_name == "Im1"

      assert %Object{value: %Stream{} = stream} =
               Document.fetch_object!(
                 document,
                 image.reference
               )

      assert stream.dictionary["Type"] == {:name, "XObject"}
      assert stream.dictionary["Subtype"] == {:name, "Image"}
      assert stream.dictionary["ColorSpace"] == {:name, "DeviceRGB"}
      assert stream.dictionary["Filter"] == {:name, "DCTDecode"}
    end

    test "registers grayscale JPEG color space" do
      {document, image} =
        Document.new()
        |> Document.register_jpeg(jpeg(10, 20, 1))

      stream =
        document
        |> Document.fetch_object!(image.reference)
        |> Map.fetch!(:value)

      assert stream.dictionary["ColorSpace"] == {:name, "DeviceGray"}
    end

    test "registers CMYK JPEG color space with decode inversion" do
      {document, image} =
        Document.new()
        |> Document.register_jpeg(jpeg(10, 20, 4))

      stream =
        document
        |> Document.fetch_object!(image.reference)
        |> Map.fetch!(:value)

      assert stream.dictionary["ColorSpace"] == {:name, "DeviceCMYK"}
      assert stream.dictionary["Decode"] == [1, 0, 1, 0, 1, 0, 1, 0]
    end

    test "deduplicates the same image data" do
      jpeg = jpeg(10, 20, 3)
      document = Document.new()

      {document, first_image} =
        Document.register_jpeg(document, jpeg)

      object_count =
        Document.object_count(document)

      {document, second_image} =
        Document.register_jpeg(document, jpeg)

      assert first_image == second_image
      assert Document.object_count(document) == object_count
      assert ImageRegistry.count(document.image_registry) == 1
    end

    test "registers different images separately" do
      document = Document.new()

      {document, first_image} =
        Document.register_jpeg(
          document,
          jpeg(10, 20, 3)
        )

      {document, second_image} =
        Document.register_jpeg(
          document,
          jpeg(11, 20, 3)
        )

      assert first_image.reference != second_image.reference
      assert first_image.resource_name == "Im1"
      assert second_image.resource_name == "Im2"
      assert ImageRegistry.count(document.image_registry) == 2
    end

    test "rejects invalid image binaries" do
      assert_raise ArgumentError, ~r/not a valid JPEG/, fn ->
        Document.register_jpeg(
          Document.new(),
          "not a JPEG"
        )
      end
    end

    test "rejects truncated JPEG binaries" do
      assert_raise ArgumentError, ~r/truncated segment/, fn ->
        Document.register_jpeg(
          Document.new(),
          <<0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08>>
        )
      end
    end
  end

  describe "register_image/2" do
    test "registers RGB PNG images as Flate XObjects" do
      png = png(2, 1, 8, 2, <<0, 255, 0, 0, 0, 255, 0>>)
      document = Document.new()

      {document, image} =
        Document.register_image(
          document,
          png
        )

      assert image.format == :png
      assert image.width == 2
      assert image.height == 1
      assert image.color_space == :device_rgb
      assert image.resource_name == "Im1"

      assert %Object{value: %Stream{} = stream} =
               Document.fetch_object!(
                 document,
                 image.reference
               )

      assert stream.dictionary["Type"] == {:name, "XObject"}
      assert stream.dictionary["Subtype"] == {:name, "Image"}
      assert stream.dictionary["ColorSpace"] == {:name, "DeviceRGB"}
      assert stream.dictionary["Filter"] == {:name, "FlateDecode"}

      assert stream.dictionary["DecodeParms"] == %{
               "Predictor" => 15,
               "Colors" => 3,
               "BitsPerComponent" => 8,
               "Columns" => 2
             }

      assert Stream.raw_data(stream) == :zlib.compress(<<0, 255, 0, 0, 0, 255, 0>>)
    end

    test "registers grayscale PNG images" do
      {document, image} =
        Document.new()
        |> Document.register_image(png(2, 1, 8, 0, <<0, 0, 255>>))

      stream =
        document
        |> Document.fetch_object!(image.reference)
        |> Map.fetch!(:value)

      assert image.format == :png
      assert stream.dictionary["ColorSpace"] == {:name, "DeviceGray"}
      assert stream.dictionary["DecodeParms"]["Colors"] == 1
    end

    test "registers grayscale alpha PNG images with a soft mask" do
      png = png(2, 1, 8, 4, <<0, 40, 128, 200, 255>>)
      document = Document.new()

      {document, image} =
        Document.register_image(
          document,
          png
        )

      assert image.format == :png
      assert image.color_space == :device_gray

      main_stream =
        document
        |> Document.fetch_object!(image.reference)
        |> Map.fetch!(:value)

      smask_reference =
        main_stream.dictionary["SMask"]

      assert %Reference{} = smask_reference
      assert main_stream.dictionary["ColorSpace"] == {:name, "DeviceGray"}
      assert main_stream.dictionary["DecodeParms"]["Colors"] == 1
      assert :zlib.uncompress(Stream.raw_data(main_stream)) == <<0, 40, 200>>

      smask_stream =
        document
        |> Document.fetch_object!(smask_reference)
        |> Map.fetch!(:value)

      assert smask_stream.dictionary["ColorSpace"] == {:name, "DeviceGray"}
      assert smask_stream.dictionary["DecodeParms"]["Colors"] == 1
      assert :zlib.uncompress(Stream.raw_data(smask_stream)) == <<0, 128, 255>>
    end

    test "registers RGBA PNG images with a soft mask" do
      png = png(2, 1, 8, 6, <<0, 255, 0, 0, 128, 0, 255, 0, 255>>)
      document = Document.new()

      {document, image} =
        Document.register_image(
          document,
          png
        )

      main_stream =
        document
        |> Document.fetch_object!(image.reference)
        |> Map.fetch!(:value)

      smask_reference =
        main_stream.dictionary["SMask"]

      assert image.color_space == :device_rgb
      assert %Reference{} = smask_reference
      assert main_stream.dictionary["ColorSpace"] == {:name, "DeviceRGB"}
      assert main_stream.dictionary["DecodeParms"]["Colors"] == 3
      assert :zlib.uncompress(Stream.raw_data(main_stream)) == <<0, 255, 0, 0, 0, 255, 0>>

      smask_stream =
        document
        |> Document.fetch_object!(smask_reference)
        |> Map.fetch!(:value)

      assert smask_stream.dictionary["Width"] == 2
      assert smask_stream.dictionary["Height"] == 1
      assert smask_stream.dictionary["ColorSpace"] == {:name, "DeviceGray"}
      assert :zlib.uncompress(Stream.raw_data(smask_stream)) == <<0, 128, 255>>
    end

    test "deduplicates the same PNG data" do
      png = png(2, 1, 8, 2, <<0, 255, 0, 0, 0, 255, 0>>)
      document = Document.new()

      {document, first_image} =
        Document.register_image(document, png)

      object_count =
        Document.object_count(document)

      {document, second_image} =
        Document.register_image(document, png)

      assert first_image == second_image
      assert Document.object_count(document) == object_count
      assert ImageRegistry.count(document.image_registry) == 1
    end

    test "deduplicates RGBA PNG data and its soft mask" do
      png = png(2, 1, 8, 6, <<0, 255, 0, 0, 128, 0, 255, 0, 255>>)
      document = Document.new()

      {document, first_image} =
        Document.register_image(document, png)

      object_count =
        Document.object_count(document)

      {document, second_image} =
        Document.register_image(document, png)

      assert first_image == second_image
      assert Document.object_count(document) == object_count
      assert ImageRegistry.count(document.image_registry) == 1

      main_stream =
        document
        |> Document.fetch_object!(first_image.reference)
        |> Map.fetch!(:value)

      assert %Reference{} = main_stream.dictionary["SMask"]
    end

    test "rejects unsupported image binaries" do
      assert_raise ArgumentError, ~r/not a valid JPEG or PNG/, fn ->
        Document.register_image(
          Document.new(),
          "not an image"
        )
      end
    end

    test "rejects non-8-bit PNG images" do
      assert_raise ArgumentError, ~r/unsupported bit depth 16/, fn ->
        Document.register_image(
          Document.new(),
          png(1, 1, 16, 2, <<0, 0, 255, 0, 0, 0, 0>>)
        )
      end
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
