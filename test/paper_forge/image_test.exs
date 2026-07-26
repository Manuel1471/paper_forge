defmodule PaperForge.ImageTest do
  use ExUnit.Case, async: true

  alias PaperForge.Image
  alias PaperForge.Reference

  @image Image.new(
           <<1, 2, 3>>,
           :jpeg,
           %{
             width: 400,
             height: 200,
             color_space: :device_rgb,
             bits_per_component: 8
           },
           <<0xFF, 0xD8>>,
           "Im1",
           Reference.new(7)
         )

  test "uses original dimensions when no display size is provided" do
    assert Image.display_size(@image) == {400, 200}
  end

  test "preserves aspect ratio when only width is provided" do
    assert Image.display_size(@image, width: 200) == {200, 100.0}
  end

  test "preserves aspect ratio when only height is provided" do
    assert Image.display_size(@image, height: 100) == {200.0, 100}
  end

  test "uses explicit width and height" do
    assert Image.display_size(@image, width: 200, height: 100) == {200, 100}
  end

  test "rejects non-positive dimensions" do
    assert_raise ArgumentError, ~r/positive numbers/, fn ->
      Image.display_size(@image, width: 0)
    end
  end
end
