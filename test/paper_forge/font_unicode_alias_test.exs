defmodule PaperForge.FontUnicodeAliasTest do
  use ExUnit.Case, async: true
  alias PaperForge.{Document, FontRegistry, Page, Stream}

  test "characters sharing a glyph keep distinct CIDs and exact ToUnicode mappings" do
    document =
      PaperForge.new()
      |> PaperForge.register_font(:unicode, path: "test/fixtures/fonts/SFNSMono.ttf")
      |> PaperForge.add_page(fn page -> Page.text(page, "Ω Ω", x: 20, y: 20, font: :unicode) end)

    font = FontRegistry.fetch!(document.font_registry, :unicode)
    assert font.unicode_to_gid[0x03A9] == font.unicode_to_gid[0x2126]
    omega = font.unicode_to_cid[0x03A9]
    ohm = font.unicode_to_cid[0x2126]
    refute omega == ohm
    %Stream{data: data} = Document.fetch_object!(document, font.to_unicode_reference).value
    data = IO.iodata_to_binary(data)

    for {cid, unicode} <- [{omega, "03A9"}, {ohm, "2126"}] do
      hex = cid |> Integer.to_string(16) |> String.pad_leading(4, "0")
      assert data =~ "<#{hex}> <#{unicode}>"
    end

    descendant = Document.fetch_object!(document, font.cid_font_reference).value
    %Stream{data: mapping} = Document.fetch_object!(document, descendant["CIDToGIDMap"]).value
    mapping = IO.iodata_to_binary(mapping)
    assert binary_part(mapping, omega * 2, 2) == binary_part(mapping, ohm * 2, 2)
  end
end
