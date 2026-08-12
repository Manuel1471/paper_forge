defmodule PaperForge.Document.Objects do
  @moduledoc false

  alias PaperForge.Document
  alias PaperForge.Object
  alias PaperForge.Reference

  @spec add(Document.t(), term()) :: {Document.t(), Reference.t()}
  def add(%Document{} = document, value) do
    object_id = document.next_object_id
    object = Object.new(object_id, value)
    reference = Reference.new(object_id)

    {%{
       document
       | objects: Map.put(document.objects, object_id, object),
         next_object_id: object_id + 1
     }, reference}
  end

  @spec update(Document.t(), Reference.t(), (term() -> term())) :: Document.t()
  def update(%Document{} = document, %Reference{object_id: object_id}, update_function)
      when is_function(update_function, 1) do
    object = Map.fetch!(document.objects, object_id)
    updated_object = %{object | value: update_function.(object.value)}
    %{document | objects: Map.put(document.objects, object_id, updated_object)}
  end

  @spec append_page(Document.t(), Reference.t()) :: Document.t()
  def append_page(%Document{} = document, %Reference{} = page_reference) do
    update(document, document.pages_reference, fn pages_dictionary ->
      pages_dictionary
      |> Map.update!("Kids", &(&1 ++ [page_reference]))
      |> Map.update!("Count", &(&1 + 1))
    end)
  end
end
