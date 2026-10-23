defmodule PaperForge.BuiltinEncodingTest do
  use ExUnit.Case, async: true
  alias PaperForge.{FontError, Page}

  test "standard fonts encode accented letters and punctuation as WinAnsi bytes" do
    content = Page.new() |> Page.text("México, más, niño • € —", x: 20, y: 20) |> Page.content()

    assert content =~
             <<"(M", 233, "xico, m", 225, "s, ni", 241, "o ", 149, " ", 128, " ", 151, ") Tj">>

    refute content =~ "México"
  end

  test "unsupported Unicode requires an embedded font instead of emitting corrupt bytes" do
    assert_raise FontError, ~r/missing|does not contain glyph/, fn ->
      Page.new() |> Page.text("漢", x: 20, y: 20) |> Page.content()
    end
  end
end
