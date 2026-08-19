defmodule PaperForge.PerformanceCacheTest do
  use ExUnit.Case, async: true

  alias PaperForge.Compression
  alias PaperForge.Flow
  alias PaperForge.PerformanceCache
  alias PaperForge.TextMetrics

  setup do
    PerformanceCache.reset()
    :ok
  end

  test "reuses repeated text measurements in the current render process" do
    first = TextMetrics.line_width("Repeated report heading", font: :helvetica, size: 12)
    second = TextMetrics.line_width("Repeated report heading", font: :helvetica, size: 12)

    assert first == second
    assert PerformanceCache.stats().text_width == %{hits: 1, misses: 1}
  end

  test "reuses short repeated text measurements" do
    assert TextMetrics.line_width("Q4", font: :helvetica, size: 12) > 0
    assert TextMetrics.line_width("Q4", font: :helvetica, size: 12) > 0
    assert PerformanceCache.stats().text_width == %{hits: 1, misses: 1}
  end

  test "reuses deterministic Flate output" do
    content = :binary.copy("BT /F1 12 Tf (PaperForge) Tj ET\n", 100)

    first = Compression.flate(content)
    second = Compression.flate(content)

    assert first == second
    assert Compression.inflate(second) == content
    assert PerformanceCache.stats().flate == %{hits: 1, misses: 1}
  end

  test "does not confuse different compression inputs of equal size" do
    first = Compression.flate("AAAA")
    second = Compression.flate("BBBB")

    assert first != second
    assert Compression.inflate(first) == "AAAA"
    assert Compression.inflate(second) == "BBBB"
  end

  test "keeps cache entries process-local" do
    text = "Parent process measurement"
    TextMetrics.line_width(text, font: :helvetica, size: 12)

    task =
      Task.async(fn ->
        PerformanceCache.reset()
        TextMetrics.line_width(text, font: :helvetica, size: 12)
        PerformanceCache.stats()
      end)

    assert Task.await(task).text_width == %{hits: 0, misses: 1}
    assert PerformanceCache.stats().text_width == %{hits: 0, misses: 1}
  end

  test "namespace limits evict only the oldest cache entry" do
    assert PerformanceCache.fetch(:tiny, :first, fn -> 1 end, 2) == 1
    assert PerformanceCache.fetch(:tiny, :second, fn -> 2 end, 2) == 2
    assert PerformanceCache.fetch(:other, :kept, fn -> 3 end, 1) == 3
    assert PerformanceCache.fetch(:tiny, :third, fn -> 3 end, 2) == 3

    assert PerformanceCache.fetch(:other, :kept, fn -> :miss end, 1) == 3
    assert PerformanceCache.fetch(:tiny, :second, fn -> :preserved end, 2) == 2
    assert PerformanceCache.fetch(:tiny, :first, fn -> :evicted end, 2) == :evicted
  end

  test "does not retain oversized compression input in the process cache" do
    content = :binary.copy("x", 256 * 1_024 + 1)

    assert is_binary(Compression.flate(content))
    refute Map.has_key?(PerformanceCache.stats(), :flate)
  end

  test "reuses default table column widths across large row sets" do
    rows = List.duplicate(["North", "$42M", "12.4%"], 40)

    {_document, report} =
      PaperForge.layout(
        PaperForge.new(),
        fn flow ->
          Flow.table(flow, ["Region", "Revenue", "Growth"], rows,
            size: 9,
            repeat_header: true
          )
        end,
        page_options: [size: {360, 360}, margins: 24]
      )

    assert report.pages >= 1
    assert %{hits: hits, misses: 1} = PerformanceCache.stats().table_column_widths
    assert hits >= length(rows)
  end
end
