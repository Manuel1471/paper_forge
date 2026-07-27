defmodule PaperForge.FontRegistryIntegrationTest do
  use ExUnit.Case, async: true

  alias PaperForge.Document
  alias PaperForge.FontError
  alias PaperForge.FontRegistry

  test "reuses the same registered font" do
    document = Document.new()

    {document, first_font} =
      Document.register_font(
        document,
        :helvetica
      )

    object_count =
      Document.object_count(document)

    {document, second_font} =
      Document.register_font(
        document,
        :helvetica
      )

    assert first_font == second_font

    assert Document.object_count(document) ==
             object_count
  end

  test "registers additional fonts with unique resource names" do
    document = Document.new()

    {document, helvetica} =
      Document.register_font(
        document,
        :helvetica
      )

    {document, bold} =
      Document.register_font(
        document,
        :helvetica_bold
      )

    assert helvetica.resource_name == "F1"
    assert bold.resource_name == "F2"

    assert helvetica.reference !=
             bold.reference

    assert Document.object_count(document) == 4
  end

  test "registers standard built-in fonts on demand" do
    font_expectations = [
      helvetica_bold: "Helvetica-Bold",
      helvetica_oblique: "Helvetica-Oblique",
      times_roman: "Times-Roman",
      courier: "Courier",
      symbol: "Symbol",
      zapf_dingbats: "ZapfDingbats"
    ]

    {document, fonts} =
      Enum.reduce(
        font_expectations,
        {Document.new(), []},
        fn {font_key, _base_font}, {document, fonts} ->
          {document, font} =
            Document.register_font(
              document,
              font_key
            )

          {
            document,
            [
              {
                font_key,
                font
              }
              | fonts
            ]
          }
        end
      )

    fonts_by_key =
      Map.new(fonts)

    Enum.each(font_expectations, fn {font_key, base_font} ->
      font =
        Map.fetch!(
          fonts_by_key,
          font_key
        )

      assert font.base_font == base_font
      assert Document.fetch_object!(document, font.reference)
    end)

    resource_names =
      document.font_registry
      |> FontRegistry.all()
      |> Enum.map(& &1.resource_name)

    assert resource_names == [
             "F1",
             "F2",
             "F3",
             "F4",
             "F5",
             "F6"
           ]
  end

  test "rejects unknown fonts" do
    assert_raise FontError, ~r/font :unknown_font has not been registered/, fn ->
      Document.register_font(
        Document.new(),
        :unknown_font
      )
    end
  end
end
