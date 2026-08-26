defmodule PaperForge.DocumentLimitsTest do
  use ExUnit.Case, async: true

  alias PaperForge.{Document, LimitError, Stream}

  test "document limits bound the writer before serialization" do
    document = PaperForge.new(limits: [max_objects: 2])

    {document, _reference} =
      Document.add_object(document, "one object beyond the catalog and page tree")

    assert_raise LimitError, ~r/max_objects exceeded/, fn -> PaperForge.to_binary(document) end
  end

  test "writer options can tighten document limits without mutating the document" do
    document = PaperForge.new()

    assert_raise LimitError, ~r/max_objects exceeded/, fn ->
      PaperForge.to_binary(document, max_objects: 1)
    end

    assert is_binary(PaperForge.to_binary(document))
  end

  test "stream and nested value limits are enforced" do
    {stream_document, _reference} =
      PaperForge.new()
      |> Document.add_object(Stream.new("0123456789"))

    assert_raise LimitError, ~r/max_uncompressed_stream_bytes exceeded/, fn ->
      PaperForge.to_binary(stream_document, max_uncompressed_stream_bytes: 5)
    end

    {nested_document, _reference} =
      PaperForge.new()
      |> Document.add_object(%{"one" => %{"two" => %{"three" => "value"}}})

    assert_raise LimitError, ~r/max_recursion_depth exceeded/, fn ->
      PaperForge.to_binary(nested_document, max_recursion_depth: 2)
    end
  end
end
