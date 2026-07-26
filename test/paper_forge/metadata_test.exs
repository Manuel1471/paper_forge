defmodule PaperForge.MetadataTest do
  use ExUnit.Case, async: true

  alias PaperForge.Metadata
  alias PaperForge.StringEncoding

  test "encodes Latin-1 metadata as literal strings" do
    dictionary =
      Metadata.new(
        title: "Reporte de México",
        author: "Manuel García"
      )
      |> Metadata.to_dictionary()

    assert dictionary["Title"] == "Reporte de M\xE9xico"
    assert dictionary["Author"] == "Manuel Garc\xEDa"
  end

  test "encodes non-Latin-1 metadata as UTF-16BE hex strings" do
    dictionary =
      Metadata.new(subject: "Información 日本語")
      |> Metadata.to_dictionary()

    assert {:hex_string, encoded} = dictionary["Subject"]
    assert StringEncoding.utf16be?(encoded)
    assert encoded == StringEncoding.utf16be("Información 日本語")
  end
end
