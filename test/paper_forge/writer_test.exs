defmodule PaperForge.WriterTest do
  use ExUnit.Case, async: true

  alias PaperForge.Page

  describe "to_binary/1" do
    test "generates a complete compressed PDF binary" do
      pdf =
        PaperForge.new()
        |> PaperForge.add_page(fn page ->
          Page.text(
            page,
            "Hello",
            x: 72,
            y: 750,
            size: 24
          )
        end)
        |> PaperForge.to_binary()

      assert pdf =~ "%PDF-1.7"
      assert pdf =~ "/Type /Catalog"
      assert pdf =~ "/Type /Pages"
      assert pdf =~ "/Type /Page"
      assert pdf =~ "/BaseFont /Helvetica"
      assert pdf =~ "/Filter /FlateDecode"
      assert pdf =~ "xref"
      assert pdf =~ "trailer"
      assert pdf =~ "/Root 2 0 R"
      assert pdf =~ "startxref"
      assert pdf =~ "%%EOF"
    end

    test "generates an uncompressed PDF when compression is disabled" do
      pdf =
        PaperForge.new(compress: false)
        |> PaperForge.add_page(fn page ->
          Page.text(
            page,
            "Hello",
            x: 72,
            y: 750,
            size: 24
          )
        end)
        |> PaperForge.to_binary()

      assert pdf =~ "%PDF-1.7"
      assert pdf =~ "(Hello) Tj"
      refute pdf =~ "/FlateDecode"
    end

    test "uses the configured PDF version in the header" do
      pdf =
        PaperForge.new(pdf_version: "1.4")
        |> PaperForge.to_binary()

      assert pdf =~ "%PDF-1.4"
    end

    test "includes the correct page count" do
      pdf =
        PaperForge.new()
        |> PaperForge.add_page(fn page ->
          Page.text(
            page,
            "Page one",
            x: 72,
            y: 750
          )
        end)
        |> PaperForge.add_page(fn page ->
          Page.text(
            page,
            "Page two",
            x: 72,
            y: 750
          )
        end)
        |> PaperForge.to_binary()

      assert pdf =~ "/Count 2"
    end

    test "xref offsets point to the beginning of each object" do
      pdf =
        PaperForge.new()
        |> PaperForge.metadata(
          title: "Reporte de México",
          author: "Manuel García"
        )
        |> PaperForge.add_page(fn page ->
          Page.text(
            page,
            "One",
            x: 72,
            y: 750
          )
        end)
        |> PaperForge.add_page(fn page ->
          Page.text(
            page,
            "Two",
            x: 72,
            y: 750,
            font: :courier
          )
        end)
        |> PaperForge.to_binary()

      assert_xref_offsets(pdf)
    end

    test "generates a structurally consistent multi-page compressed PDF" do
      jpeg = jpeg(64, 32, 3)

      pdf =
        PaperForge.new()
        |> PaperForge.metadata(
          title: "Reporte de México",
          author: "Manuel García",
          subject: "Información 日本語"
        )
        |> PaperForge.add_page(fn page ->
          page
          |> Page.text("First", x: 72, y: 750, font: :helvetica_bold)
          |> Page.image(jpeg, x: 72, y: 680, width: 64)
        end)
        |> PaperForge.add_page(fn page ->
          page
          |> Page.text("Second", x: 72, y: 750, font: :courier)
          |> Page.image(jpeg, x: 72, y: 680, width: 32)
        end)
        |> PaperForge.to_binary()

      assert pdf =~ "/Count 2"
      assert pdf =~ "/BaseFont /Helvetica-Bold"
      assert pdf =~ "/BaseFont /Courier"
      assert pdf =~ "/XObject"
      assert pdf =~ "/Im1"
      refute pdf =~ "/Im2"
      assert pdf =~ "/Filter /FlateDecode"
      assert pdf =~ "/Info "
      assert_xref_offsets(pdf)
    end
  end

  defp assert_xref_offsets(pdf) do
    entries = xref_entries(pdf)

    Enum.each(entries, fn {object_id, offset} ->
      marker =
        "#{object_id} 0 obj"

      assert binary_part(
               pdf,
               offset,
               byte_size(marker)
             ) == marker
    end)
  end

  defp xref_entries(pdf) do
    [_match, size, body] =
      Regex.run(
        ~r/xref\n0 (\d+)\n0000000000 65535 f \n(.+?)trailer\n/s,
        pdf
      )

    expected_entries =
      String.to_integer(size) - 1

    body
    |> String.split("\n", trim: true)
    |> Enum.take(expected_entries)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, object_id} ->
      case Regex.run(~r/^(\d{10}) 00000 n $/, line) do
        [_, offset] ->
          [
            {
              object_id,
              String.to_integer(offset)
            }
          ]

        nil ->
          []
      end
    end)
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

  test "incremental file writing matches binary serialization" do
    document =
      PaperForge.new()
      |> PaperForge.add_page(fn page ->
        Page.text(page, "Incremental output", x: 72, y: 750, size: 18)
      end)

    path =
      Path.join(
        System.tmp_dir!(),
        "paper_forge_incremental_#{System.unique_integer([:positive])}.pdf"
      )

    on_exit(fn -> File.rm(path) end)

    assert :ok = PaperForge.write(document, path)
    assert File.read!(path) == PaperForge.to_binary(document)
  end
end
