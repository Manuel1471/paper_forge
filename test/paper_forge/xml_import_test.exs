defmodule PaperForge.XMLImportTest do
  use ExUnit.Case, async: false
  alias PaperForge.Import.XML

  test "untrusted element and attribute names do not allocate atoms" do
    XML.parse!(~s(<root arbitrary="value">niñez €</root>))
    names = for i <- 1..200, do: "pf_untrusted_#{i}_#{System.unique_integer([:positive])}"
    inputs = Enum.map(names, &"<#{&1} attr_#{&1}=\"value\">text</#{&1}>")
    before = :erlang.system_info(:atom_count)
    Enum.each(inputs, &XML.parse!/1)
    assert :erlang.system_info(:atom_count) == before
  end

  test "Unicode and namespace declarations survive safe serialization" do
    source =
      ~s(<svg xmlns="http://www.w3.org/2000/svg"><text title="A &amp; B">Niñez € 日本語</text></svg>)

    serialized = source |> XML.parse!() |> XML.serialize()
    assert serialized =~ "Niñez € 日本語"
    assert serialized =~ "A &amp; B"
    assert serialized =~ "xmlns="
    assert XML.parse!(serialized)
  end

  test "entity declarations and excessive depth fail explicitly" do
    assert_raise ArgumentError, fn ->
      XML.parse!(
        ~s(<!DOCTYPE svg [<!ENTITY secret SYSTEM "file:///nonexistent/paperforge-secret">]><svg>&secret;</svg>)
      )
    end

    assert_raise ArgumentError, fn ->
      XML.parse!(String.duplicate("<g>", 130) <> String.duplicate("</g>", 130))
    end

    assert_raise ArgumentError, fn -> XML.parse!("<svg/> trailing") end
  end
end
