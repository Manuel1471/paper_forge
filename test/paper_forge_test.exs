defmodule PaperForgeTest do
  use ExUnit.Case
  doctest PaperForge

  test "greets the world" do
    assert PaperForge.hello() == :world
  end
end
