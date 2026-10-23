defmodule PaperForge.PDF.FiltersTest do
  use ExUnit.Case, async: true
  alias PaperForge.PDF.Filters
  alias PaperForge.Stream

  defp stream(data, filter, params \\ nil) do
    Stream.new(data, dictionary: %{"Filter" => filter, "DecodeParms" => params})
  end

  test "decodes filter chains in order and bounds the expanded data" do
    data = :binary.copy("object data\n", 2000)
    compressed = :zlib.compress(data)

    value =
      stream(Base.encode16(compressed) <> ">", [{:name, "ASCIIHexDecode"}, {:name, "FlateDecode"}])

    assert {:ok, ^data} = Filters.decode(value)
    assert {:error, {:max_stream_size_exceeded, 1000}} = Filters.decode(value, 1000)

    assert {:error, :invalid_flate_stream} =
             Filters.decode(stream("garbage", {:name, "FlateDecode"}))
  end

  test "ASCII85 supports full, partial, and zero groups and rejects overflow" do
    assert {:ok, "Hello, world!"} =
             Filters.decode(stream("87cURD_*#TDfTZ)+T~>", {:name, "ASCII85Decode"}))

    assert {:ok, <<0, 0, 0, 0>>} = Filters.decode(stream("z~>", {:name, "A85"}))
    assert {:error, :invalid_ascii85_stream} = Filters.decode(stream("uuuuu~>", {:name, "A85"}))
    assert {:error, :invalid_ascii85_stream} = Filters.decode(stream("!~>", {:name, "A85"}))
  end

  test "RunLength honors end marker and bounds repeated bytes" do
    value = stream(<<2, "abc", 254, ?x, 128>>, {:name, "RunLengthDecode"})
    assert {:ok, "abcxxx"} = Filters.decode(value)

    assert {:error, {:max_stream_size_exceeded, 20}} =
             Filters.decode(stream(<<129, ?x, 128>>, {:name, "RL"}), 20)

    assert {:error, :invalid_run_length_stream} =
             Filters.decode(stream(<<5, "abc">>, {:name, "RL"}))
  end

  test "reconstructs PNG predictor rows used by xref streams" do
    encoded = <<0, 1, 2, 3, 2, 3, 3, 3, 1, 7, 1, 1>>

    value =
      stream(:zlib.compress(encoded), {:name, "FlateDecode"}, %{"Predictor" => 12, "Columns" => 3})

    assert {:ok, <<1, 2, 3, 4, 5, 6, 7, 8, 9>>} = Filters.decode(value)

    assert {:error, {:unsupported_stream_filter, {:name, "DCTDecode"}}} =
             Filters.decode(stream("jpeg", {:name, "DCTDecode"}))
  end
end
