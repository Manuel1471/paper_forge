defmodule PaperForge.DocumentTest do
  use ExUnit.Case, async: true

  alias PaperForge.Document
  alias PaperForge.Reference

  test "creates the initial PDF object graph" do
    document = Document.new()

    assert map_size(document.objects) == 3
    assert document.root == Reference.new(2)
    assert document.pages == Reference.new(1)
    assert document.default_font == Reference.new(3)
    assert document.next_object_id == 4
  end

  test "adds an indirect object" do
    document = Document.new()

    {document, reference} =
      Document.add_object(document, %{
        "Type" => {:name, "Example"}
      })

    assert reference == Reference.new(4)
    assert document.next_object_id == 5
    assert Map.has_key?(document.objects, 4)
  end
end
