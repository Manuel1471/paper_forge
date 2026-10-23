defmodule PaperForge.ChartTest do
  use ExUnit.Case, async: true
  alias PaperForge.{Chart, Page, TextMetrics}

  defp draw(series, options \\ []) do
    Chart.render(
      Page.new(origin: :top_left),
      series,
      Keyword.merge([x: 20, y: 30, width: 300, height: 200], options)
    )
  end

  test "signed bars have positive geometry on both sides of zero" do
    page = draw([{"Profit", 12}, {"Loss", -8}])
    bars = for {:rectangle, options} <- page.operations, do: options
    assert length(bars) == 2

    zero =
      Enum.find_value(page.operations, fn
        {:line, options} -> if options[:width] == 0.8, do: options[:y1]
        _ -> nil
      end)

    assert Enum.any?(bars, &(&1[:y] == zero))
    assert Enum.any?(bars, &(abs(&1[:y] + &1[:height] - zero) < 0.001))
    assert Enum.all?(bars, &(&1[:height] > 0))
  end

  test "dense bars remain inside the requested width without dropping data" do
    page = draw(for(n <- 1..100, do: {"Category #{n}", n}), width: 240, gap: 20)
    bars = for {:rectangle, options} <- page.operations, do: options
    assert length(bars) == 100
    assert Enum.all?(bars, &(&1[:x] >= 20 and &1[:x] + &1[:width] <= 260))
    assert Enum.all?(bars, &(&1[:width] > 0))
  end

  test "long labels are shortened within their allocated text widths" do
    page = draw([{"An exceptionally long category title", 10}, {"Other", 20}])

    for {:text, text, options} <- page.operations do
      assert TextMetrics.line_width(text, size: options[:size], font: :helvetica) <=
               options[:width] + 0.01

      assert options[:x] >= 20
      assert options[:x] + options[:width] <= 320.01
      assert options[:y] >= 30 and options[:y] <= 230
    end
  end

  test "fractional values retain precision in automatic scale labels" do
    page = draw([{"A", 0.01}, {"B", 0.02}])
    texts = for {:text, text, _} <- page.operations, do: text
    assert "0.01" in texts
    assert "0.02" in texts
  end

  test "empty and all-zero radial data have distinct messages" do
    assert Enum.any?(draw([]).operations, &match?({:text, "No data", _}, &1))

    assert Enum.any?(
             draw([{"A", 0}], chart_type: :donut).operations,
             &match?({:text, "No positive values", _}, &1)
           )
  end

  test "a single positive pie uses a circle and legends can be disabled" do
    page = draw([{"Only", 12}], chart_type: :pie, show_legend: false)
    assert [{:circle, options}] = page.operations
    assert options[:x] == 170
  end

  test "negative radial data, invalid scales and undersized legends fail explicitly" do
    assert_raise ArgumentError, ~r/non-negative/, fn -> draw([{"A", -1}], chart_type: :pie) end
    assert_raise ArgumentError, ~r/y_min/, fn -> draw([{"A", 20}], y_max: 10) end

    assert_raise ArgumentError, ~r/legend does not fit/, fn ->
      draw(for(n <- 1..30, do: {"Category #{n}", n}), chart_type: :donut)
    end

    assert_raise ArgumentError, ~r/inner_radius/, fn ->
      draw([{"A", 1}], chart_type: :donut, inner_radius: 2)
    end
  end

  test "singleton and flat Cartesian series remain finite and renderable" do
    for type <- [:line, :area, :scatter], series <- [[{"A", 0}], [{"A", -2}, {"B", -2}]] do
      content = draw(series, chart_type: type) |> Page.content()
      refute content =~ "nan"
      refute content =~ "inf"
      assert content =~ "Tj"
    end
  end

  test "zero bars compile and signed scales expose round ticks including zero" do
    page = draw([{"A", 18}, {"B", -7}, {"C", 0}], show_values: false)
    assert length(for {:rectangle, _} <- page.operations, do: :bar) == 2
    texts = for {:text, text, _} <- page.operations, do: text
    assert Enum.all?(["-10", "0", "10", "20"], &(&1 in texts))
    assert is_binary(Page.content(page))
    assert is_binary(draw([{"A", 0}], y_min: -1, y_max: 0) |> Page.content())
  end

  test "dense category sampling preserves readable complete labels" do
    page = draw(for(n <- 1..40, do: {"Corridor #{n}", n}), show_values: false)
    labels = for {:text, "Corridor " <> _ = label, _} <- page.operations, do: label
    assert length(labels) > 1
    assert length(labels) < 40
    assert "Corridor 1" in labels
  end

  test "radial values can be hidden independently of the legend" do
    page = draw([{"Only", 12}], chart_type: :pie, show_values: false)
    assert Enum.any?(page.operations, &match?({:text_box, "Only", _}, &1))

    refute Enum.any?(page.operations, fn
             {:text_box, text, _} -> String.contains?(text, "%")
             _ -> false
           end)
  end
end
