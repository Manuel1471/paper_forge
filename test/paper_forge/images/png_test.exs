defmodule PaperForge.Images.PNGTest do
  use ExUnit.Case, async: true

  alias PaperForge.Images.PNG

  test "parses RGB PNG metadata and IDAT data" do
    compressed_data =
      :zlib.compress(<<0, 255, 0, 0, 0, 255, 0>>)

    assert {:ok, metadata} =
             PNG.parse(
               png_with_idat_chunks(
                 2,
                 1,
                 8,
                 2,
                 split_binary(compressed_data, 3)
               )
             )

    assert metadata.width == 2
    assert metadata.height == 1
    assert metadata.bits_per_component == 8
    assert metadata.components == 3
    assert metadata.color_space == :device_rgb
    refute metadata.alpha?
    assert metadata.smask_compressed_data == nil
    assert metadata.compressed_data == compressed_data
  end

  test "parses grayscale PNG metadata" do
    assert {:ok, metadata} =
             PNG.parse(png(2, 1, 8, 0, <<0, 0, 255>>))

    assert metadata.components == 1
    assert metadata.color_space == :device_gray
    refute metadata.alpha?
  end

  test "parses grayscale alpha PNG metadata and separates the soft mask" do
    assert {:ok, metadata} =
             PNG.parse(png(2, 1, 8, 4, <<0, 40, 128, 200, 255>>))

    assert metadata.components == 1
    assert metadata.source_components == 2
    assert metadata.color_space == :device_gray
    assert metadata.alpha?
    assert :zlib.uncompress(metadata.compressed_data) == <<0, 40, 200>>
    assert :zlib.uncompress(metadata.smask_compressed_data) == <<0, 128, 255>>
  end

  test "parses RGBA PNG metadata and separates the soft mask" do
    assert {:ok, metadata} =
             PNG.parse(png(2, 1, 8, 6, <<0, 255, 0, 0, 128, 0, 255, 0, 255>>))

    assert metadata.components == 3
    assert metadata.source_components == 4
    assert metadata.color_space == :device_rgb
    assert metadata.alpha?
    assert :zlib.uncompress(metadata.compressed_data) == <<0, 255, 0, 0, 0, 255, 0>>
    assert :zlib.uncompress(metadata.smask_compressed_data) == <<0, 128, 255>>
  end

  test "applies PNG scanline filters before separating alpha" do
    assert {:ok, metadata} =
             PNG.parse(png(2, 1, 8, 6, <<1, 10, 20, 30, 40, 1, 2, 3, 4>>))

    assert :zlib.uncompress(metadata.compressed_data) == <<0, 10, 20, 30, 11, 22, 33>>
    assert :zlib.uncompress(metadata.smask_compressed_data) == <<0, 40, 44>>
  end

  test "parses a 1000x1000 RGBA PNG in a reasonable time" do
    png =
      File.read!("test/fixtures/rgba_1000.png")

    {time_us, metadata} =
      :timer.tc(fn ->
        PNG.parse!(png)
      end)

    assert metadata.width == 1000
    assert metadata.height == 1000
    assert metadata.color_type == 6
    assert metadata.alpha?
    assert time_us < 1_000_000
  end

  test "rejects invalid PNG data" do
    assert PNG.parse("not a png") == {:error, :invalid_png}
  end

  test "rejects truncated PNG chunks" do
    assert PNG.parse(<<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, "IHDR">>) ==
             {:error, :truncated_chunk}
  end

  test "rejects non-8-bit PNG images" do
    assert PNG.parse(png(1, 1, 16, 2, <<0, 0, 255, 0, 0, 0, 0>>)) ==
             {:error, {:unsupported_bit_depth, 16, 2}}
  end

  defp png(width, height, bit_depth, color_type, scanlines) do
    png_with_idat_chunks(
      width,
      height,
      bit_depth,
      color_type,
      [:zlib.compress(scanlines)]
    )
  end

  defp png_with_idat_chunks(width, height, bit_depth, color_type, idat_chunks) do
    ihdr =
      <<
        width::32-big,
        height::32-big,
        bit_depth,
        color_type,
        0,
        0,
        0
      >>

    [
      <<137, 80, 78, 71, 13, 10, 26, 10>>,
      chunk("IHDR", ihdr),
      Enum.map(
        idat_chunks,
        &chunk("IDAT", &1)
      ),
      chunk("IEND", "")
    ]
    |> IO.iodata_to_binary()
  end

  defp split_binary(binary, split_at) do
    <<
      first::binary-size(^split_at),
      second::binary
    >> = binary

    [
      first,
      second
    ]
  end

  defp chunk(type, data) do
    [
      <<byte_size(data)::32-big>>,
      type,
      data,
      <<0::32-big>>
    ]
  end
end
