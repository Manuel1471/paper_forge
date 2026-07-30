defmodule PaperForge.PerformanceCacheTest do
  use ExUnit.Case, async: true

  alias PaperForge.Compression
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

  test "measures short text without cache bookkeeping" do
    assert TextMetrics.line_width("Q4", font: :helvetica, size: 12) > 0
    assert TextMetrics.line_width("Q4", font: :helvetica, size: 12) > 0
    refute Map.has_key?(PerformanceCache.stats(), :text_width)
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

  test "namespace limits reset only the full namespace" do
    assert PerformanceCache.fetch(:tiny, :first, fn -> 1 end, 2) == 1
    assert PerformanceCache.fetch(:tiny, :second, fn -> 2 end, 2) == 2
    assert PerformanceCache.fetch(:other, :kept, fn -> 3 end, 1) == 3
    assert PerformanceCache.fetch(:tiny, :third, fn -> 3 end, 2) == 3

    assert PerformanceCache.fetch(:other, :kept, fn -> :miss end, 1) == 3
    assert PerformanceCache.fetch(:tiny, :first, fn -> :evicted end, 2) == :evicted
    assert PerformanceCache.fetch(:tiny, :second, fn -> :evicted end, 2) == :evicted
  end
end
