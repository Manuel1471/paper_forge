defmodule PaperForge.DeclarativeProductionTest do
  use ExUnit.Case, async: true

  alias PaperForge.Declarative
  alias PaperForge.Declarative.Registry
  alias PaperForge.Flow

  test "validates deep schemas, constraints, formats, and unknown fields" do
    template = %{
      "version" => "1",
      "variables" => %{
        "name" => %{
          "type" => "string",
          "min_length" => 3,
          "max_length" => 8,
          "pattern" => "^[A-Z]"
        },
        "score" => %{"type" => "number", "min" => 0, "max" => 100},
        "color" => %{"type" => "string", "format" => "color"},
        "items" => %{
          "type" => "list",
          "min_length" => 1,
          "items" => %{
            "type" => "map",
            "required_properties" => ["label"],
            "additional_properties" => false,
            "properties" => %{"label" => %{"type" => "string"}}
          }
        }
      },
      "blocks" => []
    }

    assert :ok =
             Declarative.validate(template, %{
               name: "Aurora",
               score: 92,
               color: "#0f766e",
               items: [%{label: "Revenue"}]
             })

    assert {:error, errors} =
             Declarative.validate(template, %{
               name: "bad name",
               score: 101,
               color: "green",
               items: [%{label: "Revenue", extra: true}]
             })

    assert Enum.map(errors, & &1.code) |> Enum.sort() ==
             [:invalid_color, :maximum, :pattern, :unknown_property]

    assert {:error, [%{code: :unknown_root_field}]} =
             Declarative.validate(Map.put(template, "surprise", true), %{})
  end

  test "evaluates comparison, boolean, contains, and empty expressions" do
    template = %{
      "version" => "1",
      "variables" => %{
        "growth" => "number",
        "tags" => "list",
        "note" => "string"
      },
      "blocks" => [
        conditional(%{"left" => "{{growth}}", "operator" => "lt", "right" => 0}, "loss"),
        conditional(
          %{
            "operator" => "and",
            "values" => [
              %{"left" => "{{growth}}", "operator" => "gte", "right" => -5},
              %{"left" => "{{tags}}", "operator" => "contains", "right" => "priority"},
              %{"operator" => "not", "value" => %{"operator" => "empty", "value" => "{{note}}"}}
            ]
          },
          "qualified"
        )
      ]
    }

    assert {:ok, compiled} =
             Declarative.compile(template, %{growth: -1.2, tags: ["priority"], note: "reviewed"})

    assert compiled.flow.blocks |> Enum.reverse() |> Enum.map(& &1.content) == [
             "loss",
             "qualified"
           ]
  end

  test "renders trusted components with validated props, slots, and variants" do
    registry =
      Registry.new()
      |> Registry.component(
        :panel,
        fn props, slots, variant ->
          flow = Flow.new() |> Flow.heading("#{props["title"]} / #{variant}")

          case Map.get(slots, "body") do
            %Flow{} = body -> %{flow | blocks: body.blocks ++ flow.blocks}
            nil -> flow
          end
        end,
        props: %{"title" => %{"type" => "string", "required" => true}},
        variants: [:compact, :wide]
      )

    template = %{
      "version" => "1",
      "blocks" => [
        %{
          "component" => "panel",
          "variant" => "compact",
          "props" => %{"title" => "Executive"},
          "slots" => %{"body" => [%{"type" => "paragraph", "text" => "Slot content"}]}
        }
      ]
    }

    assert {:ok, compiled} = Declarative.compile(template, %{}, registry: registry)
    blocks = Enum.reverse(compiled.flow.blocks)
    assert Enum.map(blocks, & &1.content) == ["Executive / compact", "Slot content"]

    bad = put_in(template, ["blocks", Access.at(0), "variant"], "missing")

    assert {:error, [%{code: :trusted_component_error}]} =
             Declarative.compile(bad, %{}, registry: registry)
  end

  test "trusted components replace declarative interface stubs" do
    registry =
      Registry.new()
      |> Registry.component(
        :cover,
        fn props, _slots -> Flow.new() |> Flow.heading("Trusted #{props["title"]}") end,
        props: %{"title" => %{"type" => "string", "required" => true}}
      )

    template = %{
      "version" => "1",
      "design_system" => %{
        "components" => %{
          "cover" => %{
            "props" => %{"title" => %{"type" => "string", "required" => true}},
            "blocks" => []
          }
        }
      },
      "blocks" => [%{"component" => "cover", "props" => %{"title" => "Report"}}]
    }

    assert {:ok, offline} = Declarative.compile(template)
    assert offline.flow.blocks == []

    assert {:ok, runtime} = Declarative.compile(template, %{}, registry: registry)
    assert [%{content: "Trusted Report"}] = runtime.flow.blocks
  end

  test "supports declarative props, variants, slots, and direct cycle detection" do
    template = %{
      "version" => "1",
      "design_system" => %{
        "components" => %{
          "card" => %{
            "props" => %{"title" => %{"type" => "string", "required" => true}},
            "blocks" => [
              %{"type" => "heading", "text" => "{{title}}"},
              %{"slot" => "body"}
            ],
            "variants" => %{
              "quiet" => %{
                "blocks" => [
                  %{"type" => "paragraph", "text" => "Quiet {{title}}"},
                  %{"slot" => "body"}
                ]
              }
            }
          }
        }
      },
      "blocks" => [
        %{
          "component" => "card",
          "variant" => "quiet",
          "props" => %{"title" => "Revenue"},
          "slots" => %{"body" => [%{"type" => "paragraph", "text" => "Details"}]}
        }
      ]
    }

    assert {:ok, compiled} = Declarative.compile(template)

    assert compiled.flow.blocks |> Enum.reverse() |> Enum.map(& &1.content) == [
             "Quiet Revenue",
             "Details"
           ]

    cyclic =
      put_in(template, ["design_system", "components", "card", "blocks"], [
        %{"component" => "card", "props" => %{"title" => "Again"}}
      ])

    cyclic = put_in(cyclic, ["blocks", Access.at(0), "variant"], nil)
    assert {:error, [%{code: :component_cycle}]} = Declarative.compile(cyclic)
  end

  test "loads imports and includes inside a configured root" do
    root = temporary_directory!()

    File.write!(
      Path.join(root, "library.paperforge"),
      Jason.encode!(%{
        version: "1",
        design_system: %{styles: %{body: %{size: 9}}},
        blocks: []
      })
    )

    File.write!(
      Path.join(root, "chapter.paperforge"),
      Jason.encode!(%{
        version: "1",
        blocks: [%{type: "paragraph", text: "Imported chapter"}]
      })
    )

    main = Path.join(root, "main.paperforge")

    File.write!(
      main,
      Jason.encode!(%{
        version: "1",
        imports: ["library.paperforge"],
        includes: ["chapter.paperforge"],
        blocks: [%{type: "paragraph", text: "Main chapter", options: %{style: "body"}}]
      })
    )

    assert {:ok, template} = Declarative.load(main, root: root)
    assert {:ok, compiled} = Declarative.compile(template)

    assert compiled.flow.blocks |> Enum.reverse() |> Enum.map(& &1.content) == [
             "Imported chapter",
             "Main chapter"
           ]

    assert compiled.styles[:body][:size] == 9

    outside = Path.join(root, "outside.paperforge")
    File.write!(outside, Jason.encode!(%{version: "1", imports: ["../secret.paperforge"]}))
    assert {:error, [%{code: :forbidden_import}]} = Declarative.load(outside, root: root)
  end

  test "reports exact source line and column for semantic template errors" do
    root = temporary_directory!()
    template = Path.join(root, "invalid.paperforge")

    File.write!(
      template,
      """
      {
        "version": "1",
        "blocks": [
          {"type": "paragraph", "unknown_option": true}
        ]
      }
      """
    )

    assert {:ok, loaded} = Declarative.load(template, root: root)

    assert {:error,
            [
              %{
                code: :unknown_block_field,
                path: "$.blocks[0].unknown_option",
                source: ^template,
                line: 4,
                column: 27
              }
            ]} = Declarative.compile(loaded)
  end

  test "loads declarative component files that compose other component files" do
    root = temporary_directory!()
    components = Path.join(root, "components")
    File.mkdir_p!(components)

    File.write!(
      Path.join(components, "metric_line.paperforge"),
      Jason.encode!(%{
        version: "1",
        kind: "component",
        name: "metric_line",
        props: %{
          label: %{type: "string", required: true},
          value: %{type: "string", required: true}
        },
        slots: %{detail: %{required: false}},
        blocks: [
          %{type: "heading", text: "{{label}}: {{value}}"},
          %{slot: "detail"}
        ]
      })
    )

    File.write!(
      Path.join(components, "metrics_section.paperforge"),
      Jason.encode!(%{
        version: "1",
        kind: "component",
        name: "metrics_section",
        components: ["metric_line.paperforge"],
        props: %{metrics: %{type: "list", required: true}},
        blocks: [
          %{
            for: "metric in metrics",
            blocks: [
              %{
                component: "metric_line",
                props: %{label: "{{metric.label}}", value: "{{metric.value}}"}
              }
            ]
          }
        ]
      })
    )

    document = Path.join(root, "report.paperforge")

    File.write!(
      document,
      Jason.encode!(%{
        version: "1",
        variables: %{metrics: %{type: "list", required: true}},
        components: ["components/metrics_section.paperforge"],
        blocks: [%{component: "metrics_section", props: %{metrics: "{{metrics}}"}}]
      })
    )

    assert {:ok, template} = Declarative.load(document, root: root)

    assert {:ok, compiled} =
             Declarative.compile(template, %{
               metrics: [
                 %{label: "Revenue", value: "$12M"},
                 %{label: "Margin", value: "18%"}
               ]
             })

    assert compiled.flow.blocks |> Enum.reverse() |> Enum.map(& &1.content) == [
             "Revenue: $12M",
             "Margin: 18%"
           ]
  end

  test "validates required slots in declarative component files" do
    template = %{
      "version" => "1",
      "design_system" => %{
        "components" => %{
          "panel" => %{
            "slots" => %{"body" => %{"required" => true}},
            "blocks" => [%{"slot" => "body"}]
          }
        }
      },
      "blocks" => [%{"component" => "panel"}]
    }

    assert {:error, [%{code: :required_slot}]} = Declarative.compile(template)
  end

  test "detects cycles across declarative component files" do
    root = temporary_directory!()

    File.write!(
      Path.join(root, "a.paperforge"),
      Jason.encode!(%{
        version: "1",
        kind: "component",
        name: "a",
        components: ["b.paperforge"],
        blocks: []
      })
    )

    File.write!(
      Path.join(root, "b.paperforge"),
      Jason.encode!(%{
        version: "1",
        kind: "component",
        name: "b",
        components: ["a.paperforge"],
        blocks: []
      })
    )

    document = Path.join(root, "report.paperforge")

    File.write!(
      document,
      Jason.encode!(%{version: "1", components: ["a.paperforge"], blocks: []})
    )

    assert {:error, [%{code: :import_cycle}]} = Declarative.load(document, root: root)
  end

  test "enforces resource, expansion, data, and table limits" do
    root = temporary_directory!()
    image = Path.join(root, "image.png")
    File.write!(image, "not decoded during compilation")
    registry = Registry.new(resource_root: root, max_resource_bytes: 100)

    image_template = %{
      "version" => "1",
      "blocks" => [%{"type" => "image", "content" => "image.png"}]
    }

    assert {:ok, _compiled} = Declarative.compile(image_template, %{}, registry: registry)

    escaped = put_in(image_template, ["blocks", Access.at(0), "content"], "../image.png")

    assert {:error, [%{code: :forbidden_resource}]} =
             Declarative.compile(escaped, %{}, registry: registry)

    outside = Path.join(System.tmp_dir!(), "paper_forge_outside_#{System.unique_integer()}.png")
    link = Path.join(root, "linked.png")
    File.write!(outside, "outside")
    File.ln_s!(outside, link)
    on_exit(fn -> File.rm(outside) end)

    linked = put_in(image_template, ["blocks", Access.at(0), "content"], "linked.png")

    assert {:error, [%{code: :forbidden_resource}]} =
             Declarative.compile(linked, %{}, registry: registry)

    loop = %{
      "version" => "1",
      "variables" => %{"items" => "list"},
      "blocks" => [
        %{"for" => "item in items", "blocks" => [%{"type" => "paragraph", "text" => "{{item}}"}]}
      ]
    }

    assert {:error, [%{code: :loop_limit}]} =
             Declarative.compile(loop, %{items: [1, 2]}, limits: %{max_loop_iterations: 1})

    table = %{
      "version" => "1",
      "blocks" => [%{"type" => "table", "columns" => ["A"], "rows" => [[1], [2]]}]
    }

    assert {:error, [%{code: :table_row_limit}]} =
             Declarative.compile(table, %{}, limits: %{max_table_rows: 1})
  end

  test "provides deterministic identity, cache, migration, schema, and source locations" do
    template = %{
      "version" => "1",
      "id" => "invoice",
      "blocks" => [%{"type" => "paragraph", "text" => "Hello"}]
    }

    assert {:ok, first} = Declarative.compile_cached(template)
    assert {:ok, second} = Declarative.compile_cached(template)
    assert first.template_id == "invoice"
    assert first.template_hash == second.template_hash
    assert first == second
    assert :ok = Declarative.clear_cache()

    assert {:ok, migrated} =
             Declarative.migrate(%{"version" => "0", "schema" => %{}, "content" => []})

    assert migrated["version"] == "1"
    assert migrated["variables"] == %{}
    assert migrated["blocks"] == []
    assert File.exists?(Declarative.schema_path())

    root = temporary_directory!()
    malformed = Path.join(root, "bad.paperforge")
    File.write!(malformed, "{\n  nope\n}")

    assert {:error, [%{code: :invalid_json, source: ^malformed} = issue]} =
             Declarative.load(malformed)

    assert is_integer(issue.line) or is_nil(issue.line)
  end

  defp conditional(expression, text) do
    %{"if" => expression, "then" => [%{"type" => "paragraph", "text" => text}]}
  end

  defp temporary_directory! do
    path = Path.join(System.tmp_dir!(), "paper_forge_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
