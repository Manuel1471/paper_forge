defmodule PaperForge.Test.PDFFixture do
  alias PaperForge.Serializer

  def classic(objects, trailer \\ %{}, prefix \\ "%PDF-1.7\n", extra_entries \\ []) do
    {body, offsets} =
      Enum.reduce(objects, {prefix, []}, fn {id, generation, value}, {body, offsets} ->
        {body <> "#{id} #{generation} obj\n#{value}\nendobj\n",
         offsets ++ [{id, byte_size(body), generation, "n"}]}
      end)

    entries =
      Enum.map(offsets ++ extra_entries, fn {id, offset, generation, flag} ->
        "#{id} 1\n#{String.pad_leading(to_string(offset), 10, "0")} #{String.pad_leading(to_string(generation), 5, "0")} #{flag} \n"
      end)

    size = Enum.max(Enum.map(offsets ++ extra_entries, &elem(&1, 0)), fn -> 0 end) + 1
    trailer = Map.merge(%{"Size" => size, "Root" => PaperForge.Reference.new(2)}, trailer)

    body <>
      "xref\n" <>
      IO.iodata_to_binary(entries) <>
      "trailer\n" <>
      IO.iodata_to_binary(Serializer.encode(trailer)) <>
      "\nstartxref\n#{byte_size(body)}\n%%EOF\n"
  end

  def objects do
    [
      {1, 0, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"},
      {2, 0, "<< /Type /Catalog /Pages 1 0 R >>"},
      {3, 0, "<< /Type /Page /Parent 1 0 R /MediaBox [0 0 200 300] >>"}
    ]
  end

  def offset(pdf) do
    [_, n] = Regex.scan(~r/startxref\s+(\d+)/, pdf) |> List.last()
    String.to_integer(n)
  end

  def compressed(hybrid \\ false) do
    values = [
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Catalog /Pages 1 0 R >>",
      "<< /Type /Page /Parent 1 0 R /MediaBox [0 0 200 300] >>"
    ]

    {headers, bodies, _} =
      Enum.reduce(Enum.with_index(values, 1), {"", "", 0}, fn {body, id},
                                                              {headers, bodies, offset} ->
        {headers <> "#{id} #{offset} ", bodies <> body <> " ", offset + byte_size(body) + 1}
      end)

    data = :zlib.compress(headers <> bodies)
    prefix = "%PDF-1.7\n"
    stream_offset = byte_size(prefix)

    prefix =
      prefix <>
        "4 0 obj\n<< /Type /ObjStm /N 3 /First #{byte_size(headers)} /Filter /FlateDecode /Length #{byte_size(data)} >>\nstream\n" <>
        data <> "\nendstream\nendobj\n"

    xref_offset = byte_size(prefix)

    entries =
      <<0, 0::32, 65535::16, 2, 4::32, 0::16, 2, 4::32, 1::16, 2, 4::32, 2::16, 1,
        stream_offset::32, 0::16, 1, xref_offset::32, 0::16>>

    encoded = :zlib.compress(entries)

    prefix =
      prefix <>
        "5 0 obj\n<< /Type /XRef /Size 6 /W [1 4 2] /Root 2 0 R /Filter /FlateDecode /Length #{byte_size(encoded)} >>\nstream\n" <>
        encoded <> "\nendstream\nendobj\n"

    if hybrid do
      classic([], %{"Size" => 6, "XRefStm" => xref_offset}, prefix, [
        {0, 0, 65535, "f"},
        {1, 0, 0, "f"},
        {2, 0, 0, "f"},
        {3, 0, 0, "f"},
        {4, stream_offset, 0, "n"},
        {5, xref_offset, 0, "n"}
      ])
    else
      prefix <> "startxref\n#{xref_offset}\n%%EOF\n"
    end
  end
end
