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
end
