defmodule PaperForge.EmbeddedFontTest do
  use ExUnit.Case, async: true

  alias PaperForge.Document
  alias PaperForge.FontError
  alias PaperForge.FontRegistry
  alias PaperForge.Object
  alias PaperForge.Page
  alias PaperForge.Stream
  alias PaperForge.TextMetrics

  @font_path "test/fixtures/fonts/SFNSMono.ttf"
  @unicode_text "Información — Привет — € © ™"

  test "registers a TrueType font from a path" do
    document =
      PaperForge.new()
      |> PaperForge.register_font(
        :sfmono,
        path: @font_path
      )

    assert {:ok, font} =
             FontRegistry.fetch(
               document.font_registry,
               :sfmono
             )

    assert font.kind == :truetype
    assert font.encoding == :identity_h
    assert font.resource_name == "F1"
    assert Document.fetch_object!(document, font.reference)
  end

  test "registers a TrueType font from binary data" do
    document =
      PaperForge.new()
      |> PaperForge.register_font(
        :sfmono,
        data: File.read!(@font_path)
      )

    assert {:ok, font} =
             FontRegistry.fetch(
               document.font_registry,
               :sfmono
             )

    assert font.kind == :truetype
  end

  test "does not register the same TrueType font key twice" do
    document =
      PaperForge.new()
      |> PaperForge.register_font(
        :sfmono,
        path: @font_path
      )

    object_count =
      Document.object_count(document)

    document =
      PaperForge.register_font(
        document,
        :sfmono,
        path: @font_path
      )

    assert Document.object_count(document) == object_count
  end

  test "registers different TrueType font keys with different embedded names" do
    document =
      PaperForge.new()
      |> PaperForge.register_font(
        :sfmono_regular,
        path: @font_path
      )
      |> PaperForge.register_font(
        :sfmono_alt,
        path: @font_path
      )

    {:ok, regular} =
      FontRegistry.fetch(
        document.font_registry,
        :sfmono_regular
      )

    {:ok, alternate} =
      FontRegistry.fetch(
        document.font_registry,
        :sfmono_alt
      )

    assert regular.resource_name == "F1"
    assert alternate.resource_name == "F2"
    assert regular.base_font != alternate.base_font
  end

  test "writes Type0 font objects, FontFile2, Identity-H, and ToUnicode" do
    pdf =
      PaperForge.new()
      |> PaperForge.register_font(
        :sfmono,
        path: @font_path
      )
      |> PaperForge.add_page(fn page ->
        Page.text(
          page,
          @unicode_text,
          x: 72,
          y: 720,
          font: :sfmono,
          size: 18
        )
      end)
      |> PaperForge.to_binary()

    assert pdf =~ "/Subtype /Type0"
    assert pdf =~ "/Subtype /CIDFontType2"
    assert pdf =~ "/Encoding /Identity-H"
    assert pdf =~ "/FontFile2"
    assert pdf =~ "/ToUnicode"
  end

  test "subsets TrueType PDF widths and ToUnicode maps to used glyphs" do
    document =
      PaperForge.new()
      |> PaperForge.register_font(
        :sfmono,
        path: @font_path
      )
      |> PaperForge.add_page(fn page ->
        Page.text(
          page,
          "AB",
          x: 72,
          y: 720,
          font: :sfmono
        )
      end)

    cid_font =
      document.objects
      |> Map.values()
      |> Enum.find(fn
        %Object{value: %{"Subtype" => {:name, "CIDFontType2"}}} -> true
        _object -> false
      end)
      |> Map.fetch!(:value)

    assert widths = cid_font["W"]
    assert length(widths) <= 4
    assert Enum.all?(Enum.take_every(widths, 2), &is_integer/1)

    to_unicode =
      document.objects
      |> Map.values()
      |> Enum.find(fn
        %Object{value: %Stream{data: data}} ->
          data
          |> IO.iodata_to_binary()
          |> String.contains?("PaperForge-ToUnicode")

        _object ->
          false
      end)
      |> Map.fetch!(:value)
      |> Map.fetch!(:data)
      |> IO.iodata_to_binary()

    assert to_unicode =~ "<0041>"
    assert to_unicode =~ "<0042>"
    refute to_unicode =~ "<00F1>"
  end

  test "stores ToUnicode as a compressed stream" do
    document =
      PaperForge.new()
      |> PaperForge.register_font(
        :sfmono,
        path: @font_path
      )

    to_unicode_streams =
      document.objects
      |> Map.values()
      |> Enum.filter(fn
        %Object{value: %Stream{filters: [:flate], data: data}} ->
          data
          |> IO.iodata_to_binary()
          |> String.contains?("beginbfchar")

        _object ->
          false
      end)

    assert length(to_unicode_streams) == 1
  end

  test "uses TrueType metrics for text width" do
    document =
      PaperForge.new()
      |> PaperForge.register_font(
        :sfmono,
        path: @font_path
      )

    {:ok, font} =
      FontRegistry.fetch(
        document.font_registry,
        :sfmono
      )

    assert TextMetrics.width(
             "Información",
             font: :sfmono,
             font_instance: font,
             size: 14
           ) > 0
  end

  test "uses registered TrueType fonts inside wrapped text boxes" do
    pdf =
      PaperForge.new()
      |> PaperForge.register_font(
        :sfmono,
        path: @font_path
      )
      |> PaperForge.add_page(fn page ->
        Page.text_box(
          page,
          @unicode_text <> " " <> @unicode_text,
          x: 72,
          y: 720,
          width: 180,
          font: :sfmono,
          size: 12,
          line_height: 16
        )
      end)
      |> PaperForge.to_binary()

    assert pdf =~ "/Subtype /Type0"
    assert pdf =~ "/ToUnicode"
  end

  test "raises a clear error when a requested font has not been registered" do
    assert_raise FontError, ~r/font :missing has not been registered/, fn ->
      PaperForge.new()
      |> PaperForge.add_page(fn page ->
        Page.text(
          page,
          "Hello",
          x: 72,
          y: 720,
          font: :missing
        )
      end)
    end
  end

  test "raises a clear error for missing glyphs" do
    assert_raise FontError, ~r/does not contain glyph U\+10FFFF/, fn ->
      PaperForge.new()
      |> PaperForge.register_font(
        :sfmono,
        path: @font_path
      )
      |> PaperForge.add_page(fn page ->
        Page.text(
          page,
          <<0x10FFFF::utf8>>,
          x: 72,
          y: 720,
          font: :sfmono
        )
      end)
    end
  end
end
