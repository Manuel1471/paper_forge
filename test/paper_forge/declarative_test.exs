defmodule PaperForge.DeclarativeTest do
  use ExUnit.Case, async: true

  alias PaperForge.Declarative
  alias PaperForge.Declarative.Compiled
  alias PaperForge.DesignSystem

  @template %{
    "version" => "1",
    "variables" => %{
      "company" => %{"type" => "string", "required" => true},
      "show_note" => %{"type" => "boolean", "default" => false},
      "metrics" => %{"type" => "list", "required" => true}
    },
    "theme" => "executive",
    "layout" => "report",
    "blocks" => [
      %{"type" => "heading", "text" => "{{company}}", "options" => %{"style" => "title"}},
      %{
        "for" => "metric in metrics",
        "blocks" => [
          %{
            "component" => "metric",
            "props" => %{"label" => "{{metric.label}}", "value" => "{{metric.value}}"}
          }
        ]
      },
      %{
        "if" => "show_note",
        "then" => [%{"type" => "paragraph", "text" => "Confidential"}]
      }
    ]
  }

  test "parses JSON and reports malformed input" do
    assert {:ok, %{"version" => "1"}} = Declarative.parse(~s({"version":"1"}))
    assert {:error, [%{code: :invalid_json, path: "$"}]} = Declarative.parse("{")
  end

  test "validates required variables and declared data types" do
    assert {:error, errors} = Declarative.validate(@template, %{metrics: "wrong"})
    assert Enum.any?(errors, &(&1.code == :required and &1.path == "$.data.company"))
    assert Enum.any?(errors, &(&1.code == :invalid_type and &1.path == "$.data.metrics"))
  end

  test "compiles variables, conditions, loops, components, themes, and layouts" do
    design_system =
      DesignSystem.new()
      |> DesignSystem.token(:ink, "#17324d")
      |> DesignSystem.style(:title, %{"size" => 22, "color" => "$ink"})
      |> DesignSystem.component(:metric, %{
        "blocks" => [
          %{
            "type" => "paragraph",
            "text" => "{{label}}: {{value}}",
            "options" => %{"style" => "metric"}
          }
        ]
      })
      |> DesignSystem.layout(:report, %{
        "document" => %{"compress" => false},
        "layout_options" => %{"size" => [300, 360], "margins" => 30},
        "styles" => %{"ignored" => %{"size" => 8}}
      })
      |> DesignSystem.theme(:base, %{
        "styles" => %{"metric" => %{"size" => 9, "color" => "#555555"}}
      })
      |> DesignSystem.theme(:executive, %{
        "extends" => "base",
        "tokens" => %{"ink" => "#075985"}
      })

    assert {:ok, %Compiled{} = compiled} =
             Declarative.compile(
               @template,
               %{
                 company: "Northstar",
                 show_note: true,
                 metrics: [
                   %{label: "Revenue", value: "$12M"},
                   %{label: "Margin", value: "28%"}
                 ]
               },
               design_system: design_system
             )

    blocks = Enum.reverse(compiled.flow.blocks)
    assert Enum.map(blocks, & &1.type) == [:heading, :paragraph, :paragraph, :paragraph]

    assert Enum.map(blocks, & &1.content) == [
             "Northstar",
             "Revenue: $12M",
             "Margin: 28%",
             "Confidential"
           ]

    assert compiled.document_options[:compress] == false
    assert compiled.layout_options[:size] == {300, 360}
    assert compiled.styles[:title][:color] == PaperForge.Color.rgb255(7, 89, 133)
    assert compiled.styles[:metric][:size] == 9
  end

  test "renders compiled Layout IR into a PDF" do
    source = %{
      "version" => "1",
      "variables" => %{"name" => %{"type" => "string", "required" => true}},
      "document" => %{"compress" => false},
      "layout_options" => %{"size" => [240, 240], "margins" => 24},
      "blocks" => [
        %{"type" => "heading", "text" => "Hello {{name}}"},
        %{"type" => "table", "columns" => ["Metric", "Value"], "rows" => [["Status", "Ready"]]}
      ]
    }

    assert {:ok, document, report} = Declarative.render(source, %{name: "PaperForge"})
    assert report.pages == 1
    pdf = PaperForge.to_binary(document)
    assert pdf =~ "Hello PaperForge"
    assert pdf =~ "Ready"
  end

  test "detects design theme cycles and unknown components" do
    system =
      DesignSystem.new()
      |> DesignSystem.theme(:a, %{"extends" => "b"})
      |> DesignSystem.theme(:b, %{"extends" => "a"})

    assert {:error, [%{code: :invalid_theme}]} =
             Declarative.compile(%{"version" => "1", "theme" => "a", "blocks" => []}, %{},
               design_system: system
             )

    assert {:error, [%{code: :unknown_component}]} =
             Declarative.compile(
               %{"version" => "1", "blocks" => [%{"component" => "missing"}]},
               %{}
             )
  end
end
