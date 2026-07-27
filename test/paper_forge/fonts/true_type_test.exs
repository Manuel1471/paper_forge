defmodule PaperForge.Fonts.TrueTypeTest do
  use ExUnit.Case, async: true

  alias PaperForge.FontError
  alias PaperForge.Fonts.TrueType
  alias PaperForge.Fonts.TrueType.Subsetter

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
    assert is_integer(font.index_to_loc_format)
    assert length(font.glyph_offsets) == font.number_of_glyphs + 1
    assert is_binary(font.raw_tables["glyf"])
    assert is_binary(font.raw_tables["loca"])
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

  test "builds a physical subsetting plan" do
    font =
      @font_path
      |> File.read!()
      |> TrueType.parse!()

    {:ok, glyph_a} =
      TrueType.glyph_id(
        font,
        ?A
      )

    plan =
      Subsetter.plan(
        font,
        [glyph_a]
      )

    assert plan.binary_hash == Subsetter.binary_hash(font.data)
    assert 0 in plan.glyphs
    assert glyph_a in plan.glyphs
    assert plan.rebuild_tables == ["glyf", "loca", "hmtx", "maxp"]
    assert is_integer(plan.checksums["head"])
  end

  test "calculates TrueType table checksums with four byte padding" do
    assert Subsetter.checksum(<<1, 2, 3>>) == 0x01020300
  end
end
