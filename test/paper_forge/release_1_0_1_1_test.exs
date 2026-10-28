defmodule PaperForge.Release10And11Test do
  use ExUnit.Case, async: true
  alias PaperForge.Color
  alias PaperForge.Concurrent
  alias PaperForge.Flow
  alias PaperForge.PerformanceCache
  alias PaperForge.TextMetrics

  test "fast jobs cannot bypass resource budgets and report nonzero memory" do
    [result] = Concurrent.run([1], fn _ -> :ok end, max_reductions: 1)
    assert result.status == :resource_limit
    assert result.error.resource == :reductions

    [result] =
      Concurrent.run([1], fn _ -> :binary.copy("a", 100_000) end, max_memory_bytes: 10_000)

    assert result.status == :resource_limit
    assert result.error.resource == :memory
    [result] = Concurrent.run([1], fn _ -> :ok end)
    assert result.status == :ok
    assert result.peak_memory_bytes > 0
    assert result.garbage_collections >= 0
  end

  test "nested producers retain both cache namespaces and same-namespace entries" do
    PerformanceCache.reset()

    PerformanceCache.fetch(:outer, :one, fn ->
      PerformanceCache.fetch(:inner, :two, fn -> 2 end)
      PerformanceCache.fetch(:outer, :three, fn -> 3 end)
      1
    end)

    for {namespace, key, expected} <- [{:inner, :two, 2}, {:outer, :three, 3}, {:outer, :one, 1}] do
      assert PerformanceCache.fetch(namespace, key, fn -> flunk("lost nested cache entry") end) ==
               expected
    end
  end

  test "nested writes to the same key do not duplicate eviction entries" do
    PerformanceCache.reset()

    PerformanceCache.fetch(
      :nested,
      :one,
      fn ->
        PerformanceCache.fetch(:nested, :one, fn -> :inner end, 1)
        :outer
      end,
      1
    )

    PerformanceCache.fetch(:nested, :two, fn -> 2 end, 1)
    PerformanceCache.fetch(:nested, :three, fn -> 3 end, 1)
    assert PerformanceCache.fetch(:nested, :two, fn -> :recomputed end, 1) == :recomputed
  end

  test "explicit endnotes are retained and respect typography and spacing" do
    {doc, report} =
      PaperForge.new(compress: false)
      |> PaperForge.layout(fn flow ->
        Flow.endnotes(flow, [{7, "Explicit source"}],
          size: 10,
          color: Color.rgb(0.1, 0.2, 0.3),
          space_after: 9,
          heading_options: [size: 13, color: Color.rgb(0.2, 0.3, 0.4)]
        )
      end)

    pdf = PaperForge.to_binary(doc)
    assert pdf =~ "Explicit source"
    assert pdf =~ "13 Tf"
    assert pdf =~ "10 Tf"
    note = Enum.find(report.placements, &(&1.type == :paragraph))
    assert note.block.options[:space_after] == 9
    assert note.block.options[:color] == Color.rgb(0.1, 0.2, 0.3)
  end

  test "TOC leaders use actual glyph widths and indent without an explicit x" do
    {_doc, report} =
      PaperForge.new()
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.table_of_contents(size: 10, indent: 14, space_after: 9)
          |> Flow.page_break()
          |> Flow.heading("WWW", level: 1)
          |> Flow.heading("iiiiiiii", level: 2)
        end,
        page_options: [size: {300, 400}, margins: 30]
      )

    entries = Enum.filter(report.placements, & &1.block.options[:link_to])
    assert length(entries) == 2
    [first, second] = entries
    assert_in_delta second.x - first.x, 14, 0.001

    for entry <- entries do
      width = TextMetrics.width(entry.block.content, size: 10)
      assert entry.x + width <= 270
      assert entry.x + width > 267
      assert entry.block.options[:space_after] == 9
    end
  end
end
