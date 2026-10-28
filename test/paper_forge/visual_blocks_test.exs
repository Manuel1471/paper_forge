defmodule PaperForge.VisualBlocksTest do
  use ExUnit.Case, async: true
  alias PaperForge.{Declarative, Flow}
  alias PaperForge.Declarative.Registry
  alias PaperForge.Layout.Block

  defp text(value, opts \\ %{}),
    do: %{
      "type" => "paragraph",
      "text" => value,
      "options" => Map.merge(%{"size" => 10, "line_height" => 12, "space_after" => 0}, opts)
    }

  defp visual(type, children, opts \\ %{}),
    do: %{"type" => type, "blocks" => children, "options" => Map.put_new(opts, "space_after", 0)}

  defp render(blocks, extra \\ %{}, options \\ []) do
    template =
      Map.merge(
        %{
          "version" => "1",
          "document" => %{"compress" => false},
          "blocks" => blocks,
          "page_templates" => %{"test" => %{"size" => [300, 400], "margins" => 20}},
          "layout_options" => %{"template" => "test"}
        },
        extra
      )

    Declarative.render(template, %{}, options)
  end

  defp text_options(report, value) do
    report.rendered_pages
    |> Enum.flat_map(& &1.operations)
    |> Enum.find_value(fn
      {:text_box, ^value, opts} -> opts
      _ -> nil
    end)
  end

  test "row measures unequal cells, aligns bottoms and advances following flow" do
    row =
      visual(
        "row",
        [
          visual("container", [text("LEFT")], %{"padding" => 10}),
          visual("container", [text("RIGHT\nNEXT")], %{"padding" => 10})
        ],
        %{"column_widths" => [100, 140], "gap" => 20, "valign" => "bottom"}
      )

    assert {:ok, doc, report} = render([row, text("AFTER")])
    left = text_options(report, "LEFT")
    right = text_options(report, "RIGHT\nNEXT")
    after_opts = text_options(report, "AFTER")
    assert left[:x] == 30
    assert right[:x] == 150
    assert left[:y] == 52
    assert right[:y] == 40
    assert after_opts[:y] == 74
    assert byte_size(PaperForge.to_binary(doc)) > 0
  end

  test "grid takes the tallest item per row, not a fixed cell height" do
    cells =
      for value <- ["A", "B\nB", "C\nC\nC", "D"],
          do: visual("container", [text(value)], %{"padding" => 4})

    assert {:ok, _, report} = render([visual("grid", cells, %{"columns" => 2, "gap" => 8})])
    [grid] = report.placements
    assert grid.plan.height == 84
    assert Enum.map(grid.plan.items, & &1.y) == [0, 0, 40, 40]
  end

  test "composition moves atomically to next page and oversized content errors" do
    box = visual("container", [text("MOVES")], %{"height" => 120})
    assert {:ok, _, %{pages: 2} = report} = render([%{"type" => "spacer", "content" => 300}, box])
    assert List.last(report.placements).page_number == 2

    assert {:error, [_ | _]} =
             render([visual("container", [text(String.duplicate("line\n", 50))])])
  end

  test "nested button URI and geometry survive translation" do
    button = %{
      "type" => "button",
      "text" => "Open",
      "options" => %{"link" => "https://example.com", "width" => 80, "space_after" => 0}
    }

    layer =
      visual("container", [button], %{
        "padding" => 10,
        "width" => 120,
        "offset_x" => 30,
        "offset_y" => 40
      })

    assert {:ok, doc, report} = render([visual("overlay", [layer], %{"height" => 120})])

    {:link, uri, opts} =
      report.rendered_pages
      |> hd()
      |> Map.fetch!(:operations)
      |> Enum.find(&match?({:link, _, _}, &1))

    assert uri == "https://example.com"
    assert opts[:x] == 60
    assert opts[:y] == 70
    assert opts[:width] == 80
    assert PaperForge.to_binary(doc) =~ "/Subtype /Link"
  end

  test "invalid dimensions and unsupported nested navigation cannot silently overflow" do
    invalid = [
      visual("row", [text("A"), text("B")], %{"gap" => 300}),
      visual("container", [text("Too tall")], %{"height" => 5}),
      visual("container", [text("Wide", %{"width" => 500})]),
      visual("overlay", [visual("container", [text("X")], %{"offset_x" => -1})]),
      visual("container", [%{"type" => "page_break"}]),
      %{"type" => "button", "text" => "X", "options" => %{"link" => "javascript:alert(1)"}},
      visual("block_grid", [text("A")], %{"columns" => 0})
    ]

    for block <- invalid, do: assert(match?({:error, [_ | _]}, render([block])))
  end

  test "framed image clips locally, draws its caption and preserves following content" do
    root = Path.expand("../..", __DIR__)

    image = %{
      "type" => "framed_image",
      "content" => "assets/sample_converted.jpg",
      "options" => %{
        "width" => 60,
        "height" => 60,
        "shape" => "circle",
        "caption" => "Portrait",
        "border_width" => 1
      }
    }

    assert {:ok, doc, report} =
             render([image, text("AFTER")], %{}, registry: Registry.new(resource_root: root))

    operations = hd(report.rendered_pages).operations
    assert Enum.count(operations, &match?({:clip_start, _}, &1)) == 1
    assert Enum.count(operations, &(&1 == :clip_end)) == 1
    assert text_options(report, "Portrait")
    assert text_options(report, "AFTER")[:y] > text_options(report, "Portrait")[:y]
    assert PaperForge.to_binary(doc) =~ "W n"
    bad = put_in(image, ["content"], "../private.png")
    assert {:error, [_ | _]} = render([bad], %{}, registry: Registry.new(resource_root: root))
  end

  test "rich text supports inline italic, tokens, underline, strike and links" do
    rich = %{
      "type" => "rich_text",
      "content" => [
        %{
          "text" => "Italic",
          "options" => %{
            "style" => "italic",
            "color" => "$ink",
            "underline" => true,
            "link" => "https://example.com"
          }
        },
        %{"text" => "Old", "options" => %{"strikethrough" => true}}
      ]
    }

    assert {:ok, doc, report} =
             render([rich], %{"design_system" => %{"tokens" => %{"ink" => "#123456"}}})

    assert PaperForge.to_binary(doc) =~ "/Helvetica-Oblique"
    assert Enum.count(hd(report.rendered_pages).operations, &match?({:line, _}, &1)) == 2
  end

  test "native compositions retain children once and distinct child identities" do
    a = Block.new(:visual, :box, children: [Block.new(:paragraph, "A")])
    b = Block.new(:visual, :box, children: [Block.new(:paragraph, "B")])
    refute a.id == b.id
    refute Keyword.has_key?(a.options, :children)

    nested =
      Enum.reduce(1..20, Flow.new() |> Flow.paragraph("Deep"), fn _, flow ->
        Flow.visual(Flow.new(), :box, flow, padding: 1)
      end)

    assert byte_size(:erlang.term_to_binary(nested)) < 30_000
    assert {_doc, %{pages: 1}} = PaperForge.new() |> PaperForge.layout(fn _ -> nested end)
  end

  test "document TOC resolves destinations inside a visual box" do
    box =
      visual("container", [
        %{"type" => "heading", "text" => "Inside", "options" => %{"destination" => "inside"}}
      ])

    assert {:ok, doc, report} =
             render([%{"type" => "table_of_contents"}, %{"type" => "page_break"}, box])

    assert report.pages == 2

    toc =
      Enum.find(
        report.placements,
        &(&1.type == :paragraph and &1.block.options[:link_to] == "inside")
      )

    assert String.ends_with?(toc.block.content, "2")
    assert PaperForge.to_binary(doc) =~ "inside"
  end

  test "embedded default font sizes rich text and icon buttons consistently" do
    font = File.read!("test/fixtures/fonts/SFNSMono.ttf")

    rich = %{
      "type" => "rich_text",
      "content" => [%{"text" => "Información €"}, %{"text" => " final"}]
    }

    button = %{
      "type" => "button",
      "text" => "Continuar",
      "options" => %{
        "icon" => "arrow_right",
        "icon_size" => 16,
        "link" => "https://example.com",
        "space_after" => 0
      }
    }

    config = %{
      "fonts" => %{"custom" => %{"source" => "test:font", "subset" => true}},
      "document" => %{"default_font" => "custom", "compress" => false}
    }

    assert {:ok, doc, report} =
             render([rich, button], config, font_sources: %{"test:font" => font})

    pdf = PaperForge.to_binary(doc)
    assert pdf =~ "/FontFile2"
    refute pdf =~ "/BaseFont /Helvetica"
    placement = Enum.find(report.placements, &(&1.type == :visual))
    assert length(placement.plan.items) == 2
    assert placement.height >= 32
  end
end
