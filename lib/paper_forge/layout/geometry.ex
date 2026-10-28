defmodule PaperForge.Layout.Geometry do
  @moduledoc false

  alias PaperForge.Page

  def page!(options) do
    page = options |> Keyword.put_new(:origin, :top_left) |> Page.new()

    unless page.origin == :top_left do
      raise ArgumentError,
            "automatic layout requires origin: :top_left; use Page primitives for bottom-left coordinates"
    end

    page
  end

  def template_baseline!(page, kind, size) do
    margin = if kind == :header, do: page.margins.top, else: page.margins.bottom
    height = size * 1.2

    if margin < height do
      raise ArgumentError, "#{kind} requires a margin of at least #{height} points"
    end

    top = if kind == :header, do: 0, else: Page.content_bottom(page)
    top + (margin - height) / 2 + size
  end
end
