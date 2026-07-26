defmodule PaperForge.SerializerTest do
  use ExUnit.Case, async: true

  alias PaperForge.Reference
  alias PaperForge.Serializer
  alias PaperForge.Stream

  defp encode(value) do
    value
    |> Serializer.encode()
    |> IO.iodata_to_binary()
  end

  test "serializes null" do
    assert encode(nil) == "null"
  end

  test "serializes booleans" do
    assert encode(true) == "true"
    assert encode(false) == "false"
  end

  test "serializes integers" do
    assert encode(42) == "42"
    assert encode(-15) == "-15"
  end

  test "serializes floats without unnecessary trailing zeroes" do
    assert encode(12.5) == "12.5"
    assert encode(12.0) == "12"
  end

  test "serializes names" do
    assert encode({:name, "Catalog"}) == "/Catalog"
    assert encode({:name, "Hello World"}) == "/Hello#20World"
  end

  test "serializes literal strings" do
    assert encode("Hello") == "(Hello)"
    assert encode("Hello (PDF)") == "(Hello \\(PDF\\))"
    assert encode("a\\b") == "(a\\\\b)"
  end

  test "serializes references" do
    reference = Reference.new(8)

    assert encode(reference) == "8 0 R"
  end

  test "serializes references with a generation" do
    reference = Reference.new(8, 1)

    assert encode(reference) == "8 1 R"
  end

  test "serializes arrays" do
    assert encode([0, 0, 595, 842]) == "[0 0 595 842]"
  end

  test "serializes arrays containing references" do
    assert encode([Reference.new(3), Reference.new(4)]) ==
             "[3 0 R 4 0 R]"
  end

  test "serializes dictionaries" do
    dictionary = %{
      "Type" => {:name, "Pages"},
      "Count" => 1
    }

    assert encode(dictionary) ==
             """
             <<
             /Count 1
             /Type /Pages
             >>\
             """
  end

  test "serializes streams and calculates their length" do
    stream = Stream.new("BT\nET")

    assert encode(stream) ==
             """
             <<
             /Length 5
             >>
             stream
             BT
             ET
             endstream\
             """
  end

  test "raises for unsupported values" do
    assert_raise ArgumentError, fn ->
      encode({:unsupported, 123})
    end
  end
end
