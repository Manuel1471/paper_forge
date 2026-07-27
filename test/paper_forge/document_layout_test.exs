defmodule PaperForge.DocumentLayoutTest do
  use ExUnit.Case, async: true

  alias PaperForge.Document
  alias PaperForge.FontRegistry
  alias PaperForge.Object
  alias PaperForge.Page

  @font_path "test/fixtures/fonts/SFNSMono.ttf"

  test "uses the document default font when text omits a font" do
    pdf =
      PaperForge.new()
      |> PaperForge.register_font(
        :sfmono,
        path: @font_path
      )
      |> PaperForge.default_font(:sfmono)
      |> PaperForge.add_page(fn page ->
        Page.text(
          page,
          "Informacion — Привет",
          x: 72,
          y: 720,
          size: 14
        )
      end)
      |> PaperForge.to_binary()

    assert pdf =~ "/Subtype /Type0"
    assert pdf =~ "/Encoding /Identity-H"
  end

  test "registers font families and resolves bold italic variants" do
    document =
      PaperForge.new()
      |> PaperForge.register_font_family(
        :sfmono,
        regular: [path: @font_path],
        bold_italic: [path: @font_path]
      )
      |> PaperForge.add_page(fn page ->
        Page.text(
          page,
          "Variant text",
          x: 72,
          y: 720,
          font: :sfmono,
          weight: :bold,
          style: :italic
        )
      end)

    assert {:ok, regular} =
             FontRegistry.fetch(
               document.font_registry,
               :sfmono_regular
             )

    assert {:ok, bold_italic} =
             FontRegistry.fetch(
               document.font_registry,
               :sfmono_bold_italic
             )

    assert regular.resource_name == "F1"
    assert bold_italic.resource_name == "F2"
  end

  test "adds link annotations to page dictionaries" do
    document =
      PaperForge.new()
      |> PaperForge.add_page(fn page ->
        page
        |> Page.text("PaperForge", x: 72, y: 720)
        |> Page.link(
          "https://github.com/Manuel1471/paper_forge",
          x: 72,
          y: 700,
          width: 180,
          height: 24
        )
      end)

    page_object =
      document.objects
      |> Map.values()
      |> Enum.find(fn
        %Object{value: %{"Type" => {:name, "Page"}}} -> true
        _object -> false
      end)

    assert [%PaperForge.Reference{} = annotation_reference] =
             page_object.value["Annots"]

    annotation =
      Document.fetch_object!(
        document,
        annotation_reference
      ).value

    assert annotation["Subtype"] == {:name, "Link"}
    assert annotation["A"]["S"] == {:name, "URI"}
  end

  test "table expands into drawable operations" do
    content =
      Page.new(origin: :top_left)
      |> Page.table(
        [
          ["Name", "Score"],
          ["Ana", 10]
        ],
        x: 72,
        y: 72,
        width: 240,
        header: true
      )
      |> Page.content()

    assert content =~ " re\n"
    assert content =~ "(Name) Tj"
    assert content =~ "(Ana) Tj"
  end

  test "add_flow creates automatic page breaks" do
    blocks =
      for index <- 1..80 do
        "Parrafo #{index}: Informacion con texto suficiente para ocupar espacio."
      end

    document =
      PaperForge.new()
      |> PaperForge.add_flow(
        blocks,
        [size: {240, 260}, margins: 24],
        font: :helvetica,
        size: 10,
        line_height: 12,
        gap: 4
      )

    pages =
      document
      |> Document.fetch_object!(document.pages_reference)
      |> Map.fetch!(:value)

    assert pages["Count"] > 1
  end

  test "multilingual PDFs keep basic structural compatibility markers" do
    pdf =
      PaperForge.new()
      |> PaperForge.register_font(
        :sfmono,
        path: @font_path
      )
      |> PaperForge.default_font(:sfmono)
      |> PaperForge.add_flow(
        [
          "Español con acentos: á é í ó ú ñ ü ¿ ¡",
          "Symbols: € © ™ — …",
          "Greek and Cyrillic: Ω Ж Привет"
        ],
        [size: :a4, margins: 72],
        size: 12,
        line_height: 16
      )
      |> PaperForge.to_binary()

    assert pdf =~ "%PDF-1.7"
    assert pdf =~ "xref"
    assert pdf =~ "startxref"
    assert pdf =~ "%%EOF"
    assert pdf =~ "/ToUnicode"
  end
end
