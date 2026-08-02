defmodule PaperForge.ImportTest do
  use ExUnit.Case, async: true

  alias PaperForge.{Declarative, Flow, Import}

  test "imports HTML and its safe CSS subset into Layout IR" do
    html = """
    <style>
      h1 { color: #0f766e; }
      .lead { font-size: 14px; }
      table { width: 100%; border-color: #ccd9d7; border-width: 0.6pt; }
      th { color: #ffffff; background-color: #173f52; padding: 8pt; }
      td { color: #243b46; padding: 7pt; text-align: right; vertical-align: middle; }
      tr:nth-child(even) { background-color: #f0f7f5; }
    </style>
    <h1>Imported report</h1><p class="lead">Measured HTML content.</p>
    <table><tr><th>Metric</th><th>Value</th></tr><tr><td>Growth</td><td>12%</td></tr></table>
    """

    assert {:ok, %Flow{} = flow} = Import.html(html, strict_css: true)
    assert Enum.any?(flow.blocks, &(&1.type == :heading))
    table = Enum.find(flow.blocks, &(&1.type == :table))
    assert table.options[:cell_valign] == :middle
    assert table.options[:width] == :content
    assert table.options[:padding] == 7
    assert table.options[:header_color] == PaperForge.Color.rgb255(255, 255, 255)
    assert table.options[:header_fill_color] == PaperForge.Color.rgb255(23, 63, 82)
    assert table.options[:stripe_fill_color] == PaperForge.Color.rgb255(240, 247, 245)
    assert table.options[:stroke_color] == PaperForge.Color.rgb255(204, 217, 215)
    assert table.options[:line_width] == 0.6
    assert table.options[:cell_align] == :right
    assert table.options[:cell_valign] == :middle

    [first_row | _] = table.content.rows
    assert Enum.all?(first_row, &(&1.align == :right))
  end

  test "imports CommonMark and exposes HTML, Markdown, and math declaratively" do
    assert {:ok, %Flow{} = markdown} = Import.markdown("# Results\n\n- Fast\n- Reusable")
    assert Enum.any?(markdown.blocks, &(&1.type == :list))

    template = %{
      "version" => "1",
      "blocks" => [
        %{"type" => "markdown", "content" => "## Imported Markdown\n\nA paragraph."},
        %{"type" => "html", "content" => "<p>Imported HTML</p>"},
        %{
          "type" => "math",
          "ast" => %{
            "fraction" => %{
              "numerator" => %{"symbol" => "1"},
              "denominator" => %{"symbol" => "2"}
            }
          }
        }
      ]
    }

    assert {:ok, compiled} = Declarative.compile(template, %{})
    assert Enum.count(compiled.flow.blocks, &(&1.type == :custom)) == 1

    ordered = compiled.flow.blocks |> Enum.reverse() |> Enum.map(& &1.content)
    assert hd(ordered) == "Imported Markdown"
    assert Enum.at(ordered, 2) == "Imported HTML"
  end

  test "maps practical document CSS into layout options" do
    html = """
    <style>
      .hidden { display: none; }
      p.notice {
        font-family: Times New Roman;
        text-transform: uppercase;
        background-color: #eef7f4;
        border-color: #0a8f7a;
        border-width: 0.75pt;
        padding: 10pt;
        line-height: 15pt;
        hyphens: auto;
        widows: 3;
        orphans: 2;
        break-inside: avoid;
      }
      ul { list-style-type: none; }
      img { width: 120pt; height: 80pt; object-fit: cover; object-position: right bottom; }
    </style>
    <p class="hidden">Do not render</p>
    <p class="notice">Measured notice</p>
    <ul><li>First</li><li>Second</li></ul>
    <img src="fixture.png" />
    """

    assert {:ok, flow} = Import.html(html, strict_css: true)
    blocks = Enum.reverse(flow.blocks)

    refute Enum.any?(blocks, &(&1.content == "Do not render"))

    notice = Enum.find(blocks, &(&1.type == :paragraph))
    assert notice.content == "MEASURED NOTICE"
    assert notice.options[:font] == :times_roman
    assert notice.options[:padding] == 10
    assert notice.options[:line_height] == 15
    assert notice.options[:hyphenate]
    assert notice.options[:keep_together]
    assert notice.options[:min_lines_at_top] == 3
    assert notice.options[:min_lines_at_bottom] == 2

    list = Enum.find(blocks, &(&1.type == :list))
    assert list.options[:type] == :none

    image = Enum.find(blocks, &(&1.type == :image))
    assert image.options[:fit] == :cover
    assert image.options[:align] == :right
    assert image.options[:valign] == :bottom
  end
end
