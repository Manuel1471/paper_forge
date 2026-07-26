defmodule PaperForgeTest do
  use ExUnit.Case, async: true

  alias PaperForge.Document

  test "creates a new document" do
    assert %Document{} = PaperForge.new()
  end
end
