defmodule PaperForge.Declarative15Test do
  use ExUnit.Case, async: true
  alias PaperForge.{Declarative, Page, SVG}

  test "sections switch geometry and nested groups preserve string IDs" do
    template = %{
      "version" => "1",
      "blocks" => [
        %{
          "type" => "section",
          "name" => "Cover",
          "options" => %{
            "page_options" => %{
              "size" => [300, 400],
              "margins" => %{"top" => 20, "bottom" => 20, "left" => 20, "right" => 20}
            }
          },
          "blocks" => [
            %{
              "type" => "group",
              "options" => %{"keep_together" => true},
              "blocks" => [
                %{
                  "type" => "paragraph",
                  "text" => "Cover content",
                  "options" => %{"id" => "cover"}
                }
              ]
            }
          ]
        },
        %{
          "type" => "section",
          "name" => "Body",
          "options" => %{
            "page_options" => %{
              "size" => [500, 600],
              "margins" => %{"top" => 30, "bottom" => 30, "left" => 30, "right" => 30}
            }
          },
          "blocks" => [
            %{
              "type" => "chart",
              "content" => [["Gain", 12], ["Loss", -4]],
              "options" => %{
                "height" => 200,
                "show_grid" => true,
                "y_min" => -10,
                "y_max" => 20,
                "value_suffix" => " M"
              }
            }
          ]
        }
      ]
    }

    assert {:ok, document, report} = Declarative.render(template)
    assert report.pages == 2
    assert Enum.any?(report.placements, &(&1.id == "cover"))
    pdf = PaperForge.to_binary(document)
    assert pdf =~ "/MediaBox [0 0 300 400]"
    assert pdf =~ "/MediaBox [0 0 500 600]"
    chart = Enum.find(report.placements, &(&1.type == :chart))
    assert chart.block.options[:value_suffix] == " M"
    assert chart.block.options[:y_min] == -10
  end

  test "nested blocks are validated and count toward the compilation budget" do
    group = %{"type" => "group", "blocks" => [%{"type" => "paragraph", "text" => "Hello"}]}
    template = %{"version" => "1", "blocks" => [group]}
    assert {:error, _} = Declarative.compile(template, %{}, limits: %{max_blocks: 1})

    assert {:error, _} =
             Declarative.validate(put_in(template, ["blocks"], [%{group | "blocks" => [42]}]))
  end

  test "SVG consumes UTF-8 and preserves transformed text baselines" do
    svg =
      ~s|<svg width="100" height="100"><g transform="translate(5,10)"><text x="10" y="30" font-size="12">Índice y operación</text></g></svg>|

    page = SVG.render(Page.new(origin: :top_left), svg, x: 0, y: 0, width: 100, height: 100)
    assert [{:text, "Índice y operación", options}] = page.operations
    assert options[:x] == 15
    assert options[:y] == 40
    assert is_binary(Page.content(page))
  end
end
