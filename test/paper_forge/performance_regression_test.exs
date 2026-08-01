defmodule PaperForge.PerformanceRegressionTest do
  use ExUnit.Case, async: false

  alias PaperForge.Flow
  alias PaperForge.PerformanceCache

  @tag :performance
  test "renders and repeatedly serializes a medium report within broad guardrails" do
    rows =
      for index <- 1..250 do
        ["ROW-#{index}", "Region #{rem(index, 5)}", "$#{index * 11}", "#{rem(index, 20)}%"]
      end

    PerformanceCache.reset()
    memory_before = :erlang.memory(:total)

    {render_us, {document, report}} =
      :timer.tc(fn ->
        PaperForge.new(compress: true)
        |> PaperForge.layout(fn flow ->
          Flow.table(
            flow,
            ["Identifier", "Region", "Revenue", "Growth"],
            rows,
            repeat_header: true,
            column_widths: [120, 120, 100, 80]
          )
        end)
      end)

    {cold_us, cold_pdf} = :timer.tc(fn -> PaperForge.to_binary(document) end)
    {warm_us, warm_pdf} = :timer.tc(fn -> PaperForge.to_binary(document) end)
    memory_delta = :erlang.memory(:total) - memory_before

    assert report.pages > 1
    assert cold_pdf == warm_pdf
    assert render_us < 2_000_000
    assert cold_us < 1_000_000
    assert warm_us < 1_000_000
    assert memory_delta < 128 * 1_024 * 1_024
    assert PerformanceCache.stats().flate.hits > 0
  end
end
