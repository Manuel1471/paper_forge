defmodule PaperForge.Fonts.TrueTypeTest do
  use ExUnit.Case, async: true

  alias PaperForge.FontError
  alias PaperForge.Fonts.TrueType

  @font_path "test/fixtures/fonts/SFNSMono.ttf"

  test "parses required TrueType metrics" do
    font =
      @font_path
      |> File.read!()
      |> TrueType.parse!()

    assert font.units_per_em > 0
    assert font.number_of_glyphs > 0
    assert font.postscript_name != ""
    assert [x_min, y_min, x_max, y_max] = font.bbox
    assert x_min < x_max
    assert y_min < y_max
    assert is_integer(font.ascent)
    assert is_integer(font.descent)
  end

  test "resolves Unicode codepoints through cmap" do
    font =
      @font_path
      |> File.read!()
      |> TrueType.parse!()

    assert {:ok, glyph_id} =
             TrueType.glyph_id(
               font,
               ?ñ
             )

    assert glyph_id > 0
    assert TrueType.glyph_width(font, glyph_id) > 0
    assert TrueType.pdf_width(font, glyph_id) > 0
  end

  test "supports symbols, Greek, and Cyrillic when present in the font" do
    font =
      @font_path
      |> File.read!()
      |> TrueType.parse!()

    codepoints =
      "áéíóúñü¿¡€©™—…ΩЖ"
      |> String.to_charlist()

    for codepoint <- codepoints do
      assert {:ok, glyph_id} =
               TrueType.glyph_id(
                 font,
                 codepoint
               )

      assert glyph_id > 0
    end
  end

  test "rejects truncated fonts" do
    assert_raise FontError, ~r/invalid TrueType font|unsupported font format/, fn ->
      TrueType.parse!(<<0, 1, 0, 0, 0>>)
    end
  end

  test "rejects OpenType CFF fonts" do
    assert_raise FontError, ~r/unsupported font format/, fn ->
      TrueType.parse!(<<"OTTO", 0::size(64)>>)
    end
  end
end
