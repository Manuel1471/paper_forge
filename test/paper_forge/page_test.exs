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

  test "accepts uniform margins" do
    page = Page.new(size: {200, 300}, margins: 20)

    assert Page.content_width(page) == 160
    assert Page.content_height(page) == 260
    assert Page.content_left(page) == 20
    assert Page.content_bottom(page) == 20
    assert Page.content_top(page) == 280
  end

  test "accepts side-specific margins" do
    page =
      Page.new(
        size: {200, 300},
        origin: :top_left,
        margins: [
          top: 10,
          right: 20,
          bottom: 30,
          left: 40
        ]
      )

    assert Page.content_width(page) == 140
    assert Page.content_height(page) == 260
    assert Page.content_left(page) == 40
    assert Page.content_top(page) == 10
    assert Page.content_bottom(page) == 270
  end

  test "rejects negative margins" do
    assert_raise ArgumentError, ~r/non-negative/, fn ->
      Page.new(margins: -1)
    end
  end

  test "rejects margins larger than the page" do
    assert_raise ArgumentError, ~r/positive content width/, fn ->
      Page.new(size: {100, 100}, margins: [left: 60, right: 40])
    end
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
