defmodule PaperForge.DeclarativeCacheTest do
  use ExUnit.Case, async: true
  alias PaperForge.Declarative.Cache

  test "cache identities preserve nested term types" do
    refute Cache.hash(%{"data" => %{}}) == Cache.hash(%{"data" => []})
    refute Cache.hash(%{"data" => %{a: 1}}) == Cache.hash(%{"data" => [a: 1]})

    assert Cache.hash(Map.new([{:a, 1}, {:b, 2}])) ==
             Cache.hash(Map.new([{:b, 2}, {:a, 1}]))
  end
end
