defmodule PaperForge.PageTest do
  use ExUnit.Case, async: true

  alias PaperForge.Page

  test "creates an A4 page" do
    page = Page.new()

    assert page.width == 595
    assert page.height == 842
    assert page.operations == []
  end

  test "adds text operations" do
    page =
      Page.new()
      |> Page.text("Hello", x: 72, y: 750, size: 24)

    content =
      page
      |> Page.content()
      |> IO.iodata_to_binary()

    assert content =~ "BT"
    assert content =~ "/F1 24 Tf"
    assert content =~ "(Hello) Tj"
    assert content =~ "ET"
  end
end
