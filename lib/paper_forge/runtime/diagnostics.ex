defmodule PaperForge.Diagnostics do
  @moduledoc false

  alias PaperForge.Document
  alias PaperForge.Interoperability
  alias PaperForge.Object
  alias PaperForge.Writer

  @spec render(Document.t(), keyword()) :: {:ok, binary(), map()}
  def render(%Document{} = document, options) do
    before = process_metrics()
    started_at = System.monotonic_time(:microsecond)
    pdf = Writer.to_binary(document, options)
    elapsed = System.monotonic_time(:microsecond) - started_at
    after_metrics = process_metrics()
    inventory = Interoperability.resources(document)

    {:ok, pdf,
     %{
       pages: page_count(document),
       objects: map_size(document.objects),
       fonts: map_size(document.font_registry.fonts),
       embedded_fonts: embedded_font_count(document),
       images: map_size(document.image_registry.images),
       forms: form_count(document),
       links: annotation_count(document, "Link"),
       bookmarks: document.outline_count,
       resources: Map.new(inventory, fn {kind, references} -> {kind, length(references)} end),
       render_time_us: elapsed,
       layout_time_us: 0,
       serialization_time_us: elapsed,
       peak_memory_bytes: max(before.memory, after_metrics.memory),
       memory_delta_bytes: after_metrics.memory - before.memory,
       reductions: after_metrics.reductions - before.reductions,
       garbage_collections: max(after_metrics.gc - before.gc, 0),
       output_bytes: byte_size(pdf),
       fingerprint: :crypto.hash(:sha256, pdf) |> Base.encode16(case: :lower)
     }}
  end

  defp page_count(document),
    do: document.objects[document.pages_reference.object_id].value["Count"]

  defp embedded_font_count(document) do
    map_size(document.font_program_registry)
  end

  defp form_count(document) do
    case document.objects[document.root_reference.object_id] do
      %Object{value: %{"AcroForm" => _}} -> 1
      _ -> 0
    end
  end

  defp annotation_count(document, subtype) do
    Enum.count(document.objects, fn
      {_id, %Object{value: %{"Type" => {:name, "Annot"}, "Subtype" => {:name, ^subtype}}}} -> true
      _ -> false
    end)
  end

  defp process_metrics do
    {:memory, memory} = Process.info(self(), :memory)
    {:reductions, reductions} = Process.info(self(), :reductions)
    {:garbage_collection, gc} = Process.info(self(), :garbage_collection)
    %{memory: memory, reductions: reductions, gc: Keyword.fetch!(gc, :minor_gcs)}
  end
end
