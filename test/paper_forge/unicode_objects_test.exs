defmodule PaperForge.UnicodeObjectsTest do
  use ExUnit.Case, async: true
  alias PaperForge.{AcroForm, Document, Page, Stream, StringEncoding}
  alias PaperForge.PDF.Graph
  @text "Niñez — € “México” 日本語 🚚"

  test "styled fields fit long values and preserve alignment after editing" do
    value = String.duplicate("W", 40)

    document =
      PaperForge.new()
      |> PaperForge.add_page(Page.new())
      |> AcroForm.add_field(1, :text, "amount",
        rect: [20, 20, 120, 50],
        value: value,
        font_size: 18,
        text_align: :right,
        text_color: "#087F83",
        padding: 10
      )

    [%{dictionary: field}] = PaperForge.forms(document)
    assert field["Q"] == 2
    %Stream{data: commands} = Graph.resolve!(document, field["AP"]["N"])
    commands = IO.iodata_to_binary(commands)
    [_, size] = Regex.run(~r/([0-9.]+) Tf/, commands)
    assert String.to_float(size) < 18
    assert PaperForge.TextMetrics.width(value, size: String.to_float(size)) <= 80.001
    assert field["DA"] =~ "18 Tf"
    assert field["DA"] =~ "rg"
    updated = AcroForm.import_data(document, %{"amount" => "€ 1"})
    [%{dictionary: updated_field}] = PaperForge.forms(updated)
    assert updated_field["Q"] == 2
    assert updated_field["DA"] == field["DA"]
    assert AcroForm.export_data(updated)["amount"] == "€ 1"
  end

  test "PDF text encodings round trip without confusing Latin-1 and PDFDocEncoding" do
    for text <- [@text, "a\u00A0b", "a\u00ADb", "ñáéíóú", "€", "“quotes”", "\u0080", ""] do
      assert StringEncoding.decode(StringEncoding.auto(text)) == text
    end

    assert StringEncoding.decode(<<0xA0, 0x8D, 0xF1, 0x8E>>) == "€“ñ”"
    assert StringEncoding.decode(<<239, 187, 191>> <> @text) == @text
    assert_raise ArgumentError, fn -> StringEncoding.decode(<<254, 255, 0xD8, 0>>) end
  end

  @tag :tmp_dir
  test "metadata, file names, annotations and field labels survive write/read", %{tmp_dir: dir} do
    document =
      PaperForge.new()
      |> PaperForge.metadata(title: @text, author: "Peña", subject: "a\u00A0b")
      |> PaperForge.add_page(fn page ->
        page
        |> Page.note(@text, x: 20, y: 20)
        |> Page.annotation(:stamp, x: 50, y: 50, contents: @text, author: @text, subject: @text)
      end)
      |> PaperForge.attach(@text <> ".txt", "payload",
        description: @text,
        mime_type: "text/plain"
      )
      |> AcroForm.add_field(1, :text, @text,
        rect: [20, 100, 300, 130],
        value: "Peña € “sí”",
        tooltip: @text,
        default: "España"
      )

    path = Path.join(dir, "unicode.pdf")
    PaperForge.write!(document, path)
    document = PaperForge.open!(path)
    assert StringEncoding.decode(PaperForge.metadata(document)["Title"]) == @text
    assert StringEncoding.decode(PaperForge.metadata(document)["Subject"]) == "a\u00A0b"
    assert [%{name: name, dictionary: spec}] = PaperForge.attachments(document)
    assert name == @text <> ".txt"
    assert StringEncoding.decode(spec["UF"]) == name
    stream = Document.fetch_object!(document, spec["EF"]["UF"]).value
    assert stream.dictionary["Subtype"] == {:name, "text/plain"}
    assert AcroForm.export_data(document)[@text] == "Peña € “sí”"
    assert [%{name: @text, dictionary: field}] = PaperForge.forms(document)
    assert StringEncoding.decode(field["TU"]) == @text
    assert StringEncoding.decode(field["DV"]) == "España"

    for %{dictionary: note} <- PaperForge.annotations(document), note["Contents"] do
      assert StringEncoding.decode(note["Contents"]) == @text
    end

    assert_raise ArgumentError, ~r/already exists/, fn ->
      AcroForm.add_field(document, 1, :text, @text, rect: [20, 20, 40, 40])
    end
  end

  test "editing updates the appearance and flattening reuses selected appearances" do
    document =
      PaperForge.new()
      |> PaperForge.add_page(Page.new())
      |> AcroForm.add_field(1, :text, "name", rect: [20, 200, 300, 230], value: "Old")
      |> AcroForm.add_field(1, :checkbox, "off", rect: [20, 100, 40, 120], value: false)
      |> AcroForm.add_field(1, :text, "empty", rect: [20, 50, 300, 80])
      |> AcroForm.add_radio_group(
        "choice",
        [
          [page: 1, rect: [50, 100, 70, 120], value: "A"],
          [page: 1, rect: [80, 100, 100, 120], value: "B"]
        ],
        value: "B"
      )

    document = AcroForm.import_data(document, %{"name" => "Peña € “sí”"})
    field = Enum.find(PaperForge.forms(document), &(&1.name == "name")).dictionary
    %Stream{data: content} = Document.fetch_object!(document, field["AP"]["N"]).value
    assert IO.iodata_to_binary(content) =~ <<"Pe", 241, "a ", 128>>
    refute IO.iodata_to_binary(content) =~ "Old"
    flattened = AcroForm.flatten(document)
    assert PaperForge.forms(flattened) == []
    assert PaperForge.annotations(flattened) == []
    page = hd(Graph.pages!(flattened)).dictionary
    xobjects = page["Resources"]["XObject"] |> Map.values()
    assert field["AP"]["N"] in xobjects
    radio = Enum.filter(PaperForge.forms(document), &(&1.dictionary["Parent"] != nil))

    for widget <- radio do
      {:name, state} = widget.dictionary["AS"]
      assert widget.dictionary["AP"]["N"][state] in xobjects
    end

    assert PaperForge.to_binary(flattened) =~ "%PDF"
    assert AcroForm.flatten(PaperForge.new()) == PaperForge.new()
  end

  test "registered fonts render Unicode values in form appearances" do
    document =
      PaperForge.new()
      |> PaperForge.register_font(:unicode, path: "test/fixtures/fonts/SFNSMono.ttf")
      |> PaperForge.add_page(Page.new())
      |> AcroForm.add_field(1, :text, "日本語",
        rect: [20, 20, 300, 50],
        value: "Ω Ж",
        font: :unicode
      )
      |> AcroForm.import_data(%{"日本語" => "Ж Ω"})

    assert AcroForm.export_data(document) == %{"日本語" => "Ж Ω"}
    assert PaperForge.to_binary(AcroForm.flatten(document)) =~ "/ToUnicode"
  end

  test "XMP receives decoded Unicode and protection watermarks use WinAnsi" do
    for title <- ["México", @text] do
      document =
        PaperForge.new()
        |> PaperForge.metadata(title: title)
        |> PaperForge.add_page(Page.new())
        |> PaperForge.comply(profiles: [:pdf_ua_1], language: "es-MX")

      xmp =
        Enum.find_value(document.objects, fn {_, object} ->
          case object.value do
            %Stream{dictionary: %{"Type" => {:name, "Metadata"}}, data: data} ->
              IO.iodata_to_binary(data)

            _ ->
              nil
          end
        end)

      assert String.valid?(xmp)
      assert xmp =~ title
    end

    document =
      PaperForge.new()
      |> PaperForge.add_page(Page.new())
      |> PaperForge.Protection.watermark(text: "Peña €")

    assert Enum.any?(document.objects, fn {_, object} ->
             case object.value do
               %Stream{data: data} ->
                 :binary.match(IO.iodata_to_binary(data), <<"Pe", 241, "a ", 128>>) != :nomatch

               _ ->
                 false
             end
           end)
  end

  test "nil imported text clears both value and appearance" do
    document =
      PaperForge.new()
      |> PaperForge.add_page(Page.new())
      |> AcroForm.add_field(1, :text, "name", rect: [20, 20, 300, 50], value: "Old")
      |> AcroForm.import_data(%{"name" => nil})

    assert AcroForm.export_data(document)["name"] == nil
    assert PaperForge.annotations(AcroForm.flatten(document)) == []
  end
end
