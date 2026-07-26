defmodule PaperForge.CompressionTest do
  use ExUnit.Case, async: true

  alias PaperForge.Page

  test "compressed and uncompressed documents contain equivalent content" do
    compressed =
      build_document(true)
      |> PaperForge.to_binary()

    uncompressed =
      build_document(false)
      |> PaperForge.to_binary()

    assert compressed =~ "/FlateDecode"
    refute uncompressed =~ "/FlateDecode"

    assert uncompressed =~ "(Compression test) Tj"
    assert decompress_first_stream(compressed) =~ "(Compression test) Tj"

    assert byte_size(compressed) <
             byte_size(uncompressed)
  end

  defp build_document(compress) do
    PaperForge.new(compress: compress)
    |> PaperForge.add_page(fn page ->
      Enum.reduce(
        1..100,
        page,
        fn index, page ->
          Page.text(
            page,
            "Compression test",
            x: 72,
            y: 800 - index * 7,
            size: 10
          )
        end
      )
    end)
  end

  defp decompress_first_stream(pdf) do
    [stream] =
      Regex.run(
        ~r/stream\n(.+?)\nendstream/s,
        pdf,
        capture: :all_but_first
      )

    :zlib.uncompress(stream)
  end
end
