defmodule PaperForge.Images.JPEGTest do
  use ExUnit.Case, async: true

  alias PaperForge.Images.JPEG

  test "parses RGB JPEG metadata" do
    assert {:ok, metadata} =
             JPEG.parse(jpeg(320, 240, 3))

    assert metadata.width == 320
    assert metadata.height == 240
    assert metadata.bits_per_component == 8
    assert metadata.components == 3
    assert metadata.color_space == :device_rgb
  end

  test "parses grayscale JPEG metadata" do
    assert {:ok, metadata} =
             JPEG.parse(jpeg(80, 60, 1))

    assert metadata.color_space == :device_gray
  end

  test "parses CMYK JPEG metadata" do
    assert {:ok, metadata} =
             JPEG.parse(jpeg(80, 60, 4))

    assert metadata.color_space == :device_cmyk
  end

  test "reads EXIF orientation without decoding JPEG pixels" do
    assert {:ok, metadata} = JPEG.parse(oriented_jpeg(100, 50, 6))
    assert metadata.orientation == 6
  end

  test "rejects invalid JPEG data" do
    assert JPEG.parse("not a jpeg") == {:error, :invalid_jpeg}
  end

  test "rejects truncated JPEG segments" do
    assert JPEG.parse(<<0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08>>) ==
             {:error, :truncated_segment}
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

  defp oriented_jpeg(width, height, orientation) do
    <<"II", 42::16-little, 8::32-little, 1::16-little, 0x0112::16-little, 3::16-little,
      1::32-little, orientation::16-little, 0::16, 0::32-little>>
    |> then(fn tiff ->
      payload = <<"Exif", 0, 0, tiff::binary>>
      <<0xFF, 0xD8, remaining::binary>> = jpeg(width, height, 3)

      <<0xFF, 0xD8, 0xFF, 0xE1, byte_size(payload) + 2::16-big, payload::binary,
        remaining::binary>>
    end)
  end
end
