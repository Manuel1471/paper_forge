defmodule PaperForge.PDF.ReaderTest do
  use ExUnit.Case, async: true
  alias PaperForge.{Interoperability, Reference, Stream}
  alias PaperForge.PDF.Filters
  alias PaperForge.Test.PDFFixture, as: Fixture

  test "uses trailer root and info, including nonzero generations" do
    objects =
      Fixture.objects() ++
        [{4, 3, "<< /Type /Catalog /Pages 1 0 R >>"}, {5, 0, "<< /Title (Contract) >>"}]

    pdf = Fixture.classic(objects, %{"Root" => Reference.new(4, 3), "Info" => Reference.new(5)})
    assert {:ok, document} = Interoperability.parse_pdf(pdf)
    assert document.root_reference == Reference.new(4, 3)
    assert document.info_reference == Reference.new(5)
    assert document.source_info.cross_reference_type == :table
  end

  test "stream length protects embedded endobj/endstream and fake encryption markers" do
    data = "endobj\n9 0 obj\n<< /Encrypt /ObjStm >>\nendstream\nendobj\n[[[[[["

    pdf =
      Fixture.classic(
        Fixture.objects() ++
          [
            {4, 0, "<< /Length 5 0 R >>\nstream\n#{data}\nendstream"},
            {5, 0, to_string(byte_size(data))}
          ]
      )

    assert {:ok, document} = Interoperability.parse_pdf(pdf, max_depth: 4)
    assert %Stream{data: ^data} = document.objects[4].value
    refute Map.has_key?(document.objects, 9)
  end

  test "latest xref entries override earlier revisions and free entries mask old objects" do
    first = Fixture.classic(Fixture.objects() ++ [{4, 0, "(old)"}])
    second = Fixture.classic([{4, 2, "(new)"}], %{"Prev" => Fixture.offset(first)}, first)
    assert {:ok, document} = Interoperability.parse_pdf(second)
    assert %{generation: 2, value: "new"} = document.objects[4]
    assert length(document.source_info.revisions) == 2
    third = Fixture.classic([], %{"Prev" => Fixture.offset(second)}, second, [{4, 0, 3, "f"}])
    assert {:ok, document} = Interoperability.parse_pdf(third)
    refute Map.has_key?(document.objects, 4)
    assert length(document.source_info.revisions) == 3
  end

  test "reads compressed objects through xref streams and hybrid tables" do
    for hybrid <- [false, true] do
      assert {:ok, document} = Interoperability.parse_pdf(Fixture.compressed(hybrid))
      assert document.objects[3].value["Type"] == {:name, "Page"}
      assert document.source_info.compressed_objects == 3
      assert document.source_info.cross_reference_type == if(hybrid, do: :hybrid, else: :stream)
    end
  end

  test "rejects wrong offsets, missing EOF, and cyclic xref chains" do
    pdf = Fixture.classic(Fixture.objects())
    broken = String.replace(pdf, ~r/startxref\s+\d+/, "startxref\n99999999")
    assert {:error, :invalid_pdf_offset} = Interoperability.parse_pdf(broken)
    assert {:error, :missing_startxref} = Interoperability.parse_pdf("%PDF-1.7\n")
    cyclic = Fixture.classic([], %{"Prev" => 9})
    assert {:error, :cyclic_xref_chain} = Interoperability.parse_pdf(cyclic)
  end

  test "opens encrypted writer output only with a valid password" do
    document =
      PaperForge.new()
      |> PaperForge.add_page(fn page -> PaperForge.Page.text(page, "Secret", x: 20, y: 20) end)

    pdf =
      PaperForge.Writer.to_binary(document,
        security: [user_password: "reader", owner_password: "owner"]
      )

    assert {:error, :password_required} = Interoperability.parse_pdf(pdf)
    assert {:error, :invalid_password} = Interoperability.parse_pdf(pdf, password: "wrong")
    assert {:ok, parsed} = Interoperability.parse_pdf(pdf, password: "reader")
    assert parsed.source_info.encryption.authentication == :user
    assert {:ok, reparsed} = parsed |> PaperForge.to_binary() |> Interoperability.parse_pdf()
    assert reparsed.source_info.encryption == nil

    assert Enum.any?(reparsed.objects, fn {_, object} ->
             case object.value do
               %Stream{} = stream ->
                 case Filters.decode(stream) do
                   {:ok, data} -> data =~ "Secret"
                   _ -> false
                 end

               _ ->
                 false
             end
           end)
  end

  test "rejects cyclic stream lengths and bounds total decoded bytes" do
    cyclic =
      Fixture.classic(
        Fixture.objects() ++
          [
            {4, 0, "<< /Length 5 0 R >>\nstream\nhello\nendstream"},
            {5, 0, "6 0 R"},
            {6, 0, "5 0 R"}
          ]
      )

    assert {:error, :invalid_stream_length} = Interoperability.parse_pdf(cyclic)

    assert {:error, {:max_total_decoded_bytes_exceeded, 20}} =
             Interoperability.parse_pdf(Fixture.compressed(), max_total_decoded_bytes: 20)

    data = :zlib.compress(String.duplicate("x", 5000))

    compressed =
      Fixture.classic(
        Fixture.objects() ++
          [
            {4, 0,
             "<< /Length #{byte_size(data)} /Filter /FlateDecode >>\nstream\n#{data}\nendstream"}
          ]
      )

    assert {:error, {:max_stream_size_exceeded, 1000}} =
             Interoperability.parse_pdf(compressed, max_stream_size: 1000)
  end

  test "rewriting sparse object numbers does not allocate entries for every unused ID" do
    pdf = Fixture.classic(Fixture.objects() ++ [{1_000_000, 2, "(sparse)"}])
    assert {:ok, document} = Interoperability.parse_pdf(pdf)
    written = PaperForge.to_binary(document)
    assert byte_size(written) < 2000
    assert {:ok, reparsed} = Interoperability.parse_pdf(written)
    assert reparsed.objects[1_000_000].generation == 2
  end

  test "reads earlier PDF header versions without crashing" do
    assert {:ok, %{pdf_version: "1.3"}} =
             Interoperability.parse_pdf(Fixture.classic(Fixture.objects(), %{}, "%PDF-1.3\n"))

    assert {:ok, %{pdf_version: "2.0"}} =
             Interoperability.parse_pdf(Fixture.classic(Fixture.objects(), %{}, "%PDF-2.0\n"))
  end
end
