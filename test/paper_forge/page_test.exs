defmodule PaperForge.PageTest do
  use ExUnit.Case, async: true

  alias PaperForge.Page

  test "creates an A4 page" do
    page = Page.new()

    assert page.width == 595.28
    assert page.height == 841.89
    assert page.operations == []
  end

  test "creates a landscape page" do
    page = Page.new(size: :letter, orientation: :landscape)

    assert page.width == 792
    assert page.height == 612
  end

  test "creates a custom page size" do
    page = Page.new(size: {500, 700})

    assert page.width == 500
    assert page.height == 700
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
