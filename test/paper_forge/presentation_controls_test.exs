defmodule PaperForge.PresentationControlsTest do
  use ExUnit.Case, async: true
  alias PaperForge.{Chart, Declarative, Page, Stream}
  alias PaperForge.PDF.Graph

  defp template(blocks, styles \\ %{}, forms \\ []) do
    %{
      "version" => "1",
      "blocks" => blocks,
      "forms" => forms,
      "design_system" => %{"tokens" => %{"field" => %{"size" => 9}}, "styles" => styles}
    }
  end

  test "shared form styles resolve tokens and inheritance, with explicit field overrides" do
    source =
      template(
        [%{"type" => "paragraph", "text" => "Review"}],
        %{
          "base" => %{
            "font_size" => "$field.size",
            "border_width" => 0,
            "text_color" => "#087F83"
          },
          "compact" => %{"extends" => "base", "padding" => 4}
        },
        [
          %{
            "type" => "text",
            "name" => "name",
            "page" => 1,
            "x" => 40,
            "y" => 50,
            "width" => 180,
            "height" => 22,
            "style" => "compact",
            "font_size" => 10,
            "value" => "Peña"
          }
        ]
      )

    assert {:ok, compiled} = Declarative.compile(source)
    [form] = compiled.forms
    assert form.options[:rect] == [40, 50, 220, 72]
    assert form.options[:font_size] == 10
    assert form.options[:padding] == 4
    assert {:ok, doc, _} = Declarative.render(source)
    [field] = PaperForge.forms(doc)
    %Stream{data: data} = Graph.resolve!(doc, field.dictionary["AP"]["N"])
    content = IO.iodata_to_binary(data)
    refute content =~ " B "
    assert content =~ " f "
    assert field.dictionary["DA"] =~ "10 Tf"
  end

  test "field geometry follows theme tokens and rejects missing or invalid resolved sizes" do
    form = %{
      "type" => "text",
      "name" => "a",
      "page" => 1,
      "x" => 40,
      "y" => 50,
      "width" => 100,
      "height" => "$field.size"
    }

    source = template([%{"type" => "paragraph", "text" => "A"}], %{}, [form])

    source =
      put_in(source, ["design_system", "themes"], %{
        "larger" => %{"tokens" => %{"field" => %{"size" => 28}}}
      })

    assert {:ok, compact} = Declarative.compile(source)
    assert hd(compact.forms).options[:rect] == [40, 50, 140, 59]
    assert {:ok, larger} = Declarative.compile(Map.put(source, "theme", "larger"))
    assert hd(larger.forms).options[:rect] == [40, 50, 140, 78]

    for value <- [0, -1, "bad", nil] do
      bad = put_in(source, ["design_system", "tokens", "field", "size"], value)
      assert {:error, _} = Declarative.compile(bad)
    end
  end

  test "ambiguous geometry, invalid dimensions and cyclic form styles fail" do
    form = %{
      "type" => "text",
      "name" => "a",
      "page" => 1,
      "x" => 40,
      "y" => 50,
      "width" => 100,
      "height" => 22
    }

    for bad <- [Map.put(form, "height", 0), Map.put(form, "rect", [0, 0, 100, 20])] do
      assert {:error, _} = Declarative.compile(template([], %{}, [bad]))
    end

    styles = %{"a" => %{"extends" => "b"}, "b" => %{"extends" => "a"}}
    assert {:error, _} = Declarative.render(template([], styles, [Map.put(form, "style", "a")]))
  end

  test "formula style changes measured content and independent heading options" do
    block = %{
      "type" => "equation",
      "ast" => %{"symbol" => "x"},
      "options" => %{"style" => "formula"}
    }

    source =
      template([block], %{
        "formula" => %{"size" => 12, "heading_options" => %{"size" => 9, "space_after" => 3}}
      })

    assert {:ok, compiled} = Declarative.compile(source)
    math = Enum.find(compiled.flow.blocks, &(&1.type == :custom))
    heading = Enum.find(compiled.flow.blocks, &(&1.type == :heading))
    assert heading.options[:size] == 9
    assert heading.options[:space_after] == 3
    page = math.content.(Page.new(), %{block_x: 20, block_y: 30, block_width: 200})
    assert [{:text, "x", options}] = page.operations
    assert options[:size] == 12
    assert {:ok, _, _} = Declarative.render(source)
  end

  test "chart radial diameter and legend type can be sized independently" do
    page =
      Chart.render(Page.new(origin: :top_left), [{"Only", 1}],
        width: 300,
        height: 180,
        chart_type: :pie,
        radial_size: 64,
        legend_size: 10,
        legend_marker_size: 4,
        legend_gap: 3,
        show_values: false
      )

    assert Enum.any?(page.operations, fn
             {:circle, options} -> options[:radius] == 32
             _ -> false
           end)

    assert Enum.any?(page.operations, fn
             {:text_box, "Only", options} -> options[:size] == 10
             _ -> false
           end)

    assert_raise ArgumentError, fn ->
      Chart.render(Page.new(), [{"A", 1}], width: 200, height: 120, legend_size: 0)
    end
  end

  test "compact table borders and footnote typography are reflected in rendered content" do
    source =
      template([
        %{
          "type" => "table",
          "columns" => ["A"],
          "rows" => [["one"]],
          "options" => %{"borders" => "none", "padding" => 3, "row_height" => 18}
        },
        %{"type" => "paragraph", "text" => "See note"},
        %{
          "type" => "footnote",
          "content" => "Note",
          "options" => %{"size" => 12, "font" => "courier", "show_separator" => false}
        }
      ])

    assert {:ok, doc, report} = Declarative.render(source)
    note = Enum.find(report.placements, &(&1.type == :footnote))
    assert note.height == 15
    assert note.y == note.separator_y
    page = hd(Graph.pages!(doc)).dictionary
    %Stream{data: commands} = Graph.resolve!(doc, page["Contents"])
    content = IO.iodata_to_binary(commands)
    refute content =~ " l S"
    assert PaperForge.to_binary(doc) =~ "/Courier"
  end
end
