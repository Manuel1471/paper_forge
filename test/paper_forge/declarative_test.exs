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
        "layout_options" => %{
          "size" => [300, 360],
          "margins" => %{"top" => 42, "right" => 30, "bottom" => 36, "left" => 30}
        },
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

    assert Enum.sort(compiled.layout_options[:margins]) ==
             Enum.sort(top: 42, right: 30, bottom: 36, left: 30)

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

  test "compiles and renders security, protection, and accessibility policies" do
    source = %{
      "version" => "1",
      "variables" => %{"label" => %{"type" => "string", "required" => true}},
      "document" => %{"compress" => false},
      "metadata" => %{"title" => "{{label}}", "author" => "PaperForge"},
      "security" => %{
        "algorithm" => "aes_256",
        "permissions" => %{"print" => "high_resolution", "copy" => false}
      },
      "signature" => %{
        "algorithm" => "ps256",
        "reason" => "Executive approval",
        "location" => "Monterrey, Mexico"
      },
      "protection" => %{
        "identifier" => "urn:paperforge:declarative-test",
        "watermark" => %{"text" => "REVIEW", "opacity" => 0.1, "color" => "#64748B"},
        "policy" => %{"allowed_uri_schemes" => ["https"], "allow_attachments" => false}
      },
      "compliance" => %{"profiles" => ["pdf_ua_1"], "language" => "en-US"},
      "layout_options" => %{"size" => [300, 300], "margins" => 30},
      "blocks" => [%{"type" => "paragraph", "text" => "{{label}}"}]
    }

    assert {:ok, %Compiled{} = compiled} = Declarative.compile(source, %{label: "Secure report"})
    assert compiled.security[:algorithm] == :aes_256
    assert compiled.signature[:alg] == :PS256
    assert compiled.signature[:reason] == "Executive approval"
    refute inspect(compiled) =~ "reader-secret"

    assert {:ok, document, report} = Declarative.render(source, %{label: "Secure report"})
    assert report.pages == 1

    pdf = PaperForge.to_binary(document)
    assert pdf =~ "/StructTreeRoot"
    assert pdf =~ "(REVIEW) Tj"
    assert pdf =~ "urn:paperforge:declarative-test"

    path =
      Path.join(
        System.tmp_dir!(),
        "paper_forge_declarative_secure_#{System.unique_integer()}.pdf"
      )

    assert {:ok, %{pages: 1}} =
             Declarative.write(source, %{label: "Secure report"}, path,
               security: [user_password: "reader-secret", owner_password: "owner-secret"],
               signature: [
                 certificate:
                   {:pkcs8,
                    key_path: Path.expand("../fixtures/signing_key.pem", __DIR__),
                    cert_path: Path.expand("../fixtures/signing_cert.pem", __DIR__)}
               ]
             )

    encrypted = File.read!(path)
    assert encrypted =~ "/CFM /AESV3"
    assert encrypted =~ "/ByteRange"
    refute encrypted =~ "Secure report"
  end

  test "rejects unknown declarative protection properties" do
    source = %{"version" => "1", "protection" => %{"magic" => true}, "blocks" => []}

    assert {:error,
            [%{code: :unknown_policy_field, path: "$.protection.magic", message: message}]} =
             Declarative.compile(source)

    assert message =~ "unknown property"
  end

  test "writes security credentials declared entirely in the template" do
    source = %{
      "version" => "1",
      "security" => %{
        "algorithm" => "aes_256",
        "user_password" => "reader-secret",
        "owner_password" => "owner-secret",
        "permissions" => %{"copy" => false, "modify" => false}
      },
      "blocks" => [%{"type" => "paragraph", "text" => "Protected declarative PDF"}]
    }

    path = Path.join(System.tmp_dir!(), "paper_forge_embedded_security.pdf")
    assert {:ok, %{pages: 1}} = Declarative.write(source, %{}, path)

    pdf = File.read!(path)
    assert pdf =~ "/CFM /AESV3"
    refute pdf =~ "Protected declarative PDF"
  end

  test "registers embedded Unicode fonts from trusted declarative sources" do
    font = File.read!("test/fixtures/fonts/SFNSMono.ttf")

    template = %{
      "version" => "1",
      "fonts" => %{"document_sans" => %{"source" => "studio:sans", "subset" => true}},
      "document" => %{"default_font" => "document_sans"},
      "blocks" => [
        %{"type" => "paragraph", "text" => "Español: información y edición"},
        %{
          "type" => "columns",
          "count" => 2,
          "paragraphs" => ["Français: résumé", "Português: relatório"]
        },
        %{
          "type" => "table",
          "columns" => ["Idioma", "Muestra"],
          "rows" => [["Deutsch", "Größe"], ["Español", "Descripción"]]
        }
      ]
    }

    assert {:ok, document, _report} =
             PaperForge.Declarative.render(template, %{}, font_sources: %{"studio:sans" => font})

    pdf = PaperForge.to_binary(document)
    assert pdf =~ "/ToUnicode"
    assert pdf =~ "/FontFile2"
  end

  test "keeps untrusted declarative identifiers out of the atom table" do
    unique = "untrusted_#{System.unique_integer([:positive])}"
    font = File.read!("test/fixtures/fonts/SFNSMono.ttf")

    refute_existing_atom(unique)
    refute_existing_atom(unique <> "_style")
    refute_existing_atom(unique <> "_template")

    source = %{
      "version" => "1",
      "fonts" => %{unique => %{"source" => unique}},
      "document" => %{"default_font" => unique},
      "design_system" => %{
        "styles" => %{(unique <> "_style") => %{"size" => 11}}
      },
      "page_templates" => %{(unique <> "_template") => %{"margins" => 24}},
      "blocks" => [
        %{
          "type" => "paragraph",
          "text" => "Safe identifiers",
          "options" => %{
            "font" => unique,
            "style" => unique <> "_style",
            "template" => unique <> "_template"
          }
        }
      ]
    }

    assert {:ok, compiled} =
             Declarative.compile(source, %{}, font_sources: %{unique => font})

    assert is_atom(compiled.document_options[:default_font])
    assert Map.has_key?(compiled.styles, unique <> "_style")
    assert Map.has_key?(compiled.page_templates, unique <> "_template")

    assert {:ok, document, %{pages: 1}} =
             Declarative.render(source, %{}, font_sources: %{unique => font})

    assert PaperForge.to_binary(document) =~ "/FontFile2"

    refute_existing_atom(unique)
    refute_existing_atom(unique <> "_style")
    refute_existing_atom(unique <> "_template")
  end

  test "rejects unknown and ambiguous declarative font sources" do
    assert {:error, errors} =
             PaperForge.Declarative.compile(%{
               "version" => "1",
               "fonts" => %{"body" => %{"source" => "missing"}},
               "blocks" => []
             })

    assert Enum.any?(errors, &(&1.code == :compilation_error))

    assert {:error, errors} =
             PaperForge.Declarative.compile(%{
               "version" => "1",
               "fonts" => %{
                 "body" => %{"source" => "trusted", "path" => "font.ttf"}
               },
               "blocks" => []
             })

    assert Enum.any?(errors, &(&1.code == :ambiguous_font_source))
  end

  defp refute_existing_atom(value) do
    try do
      String.to_existing_atom(value)
      flunk("expected #{inspect(value)} not to exist as an atom")
    rescue
      ArgumentError -> :ok
    end
  end

  test "renders declarative chart variants and palettes" do
    source = %{
      "version" => "1",
      "document" => %{"compress" => false},
      "blocks" => [
        %{
          "type" => "chart",
          "content" => [["Coherent", 62], ["Damped", 23], ["Noise", 15]],
          "options" => %{
            "chart_type" => "donut",
            "colors" => ["#0f8f83", "#e76554", "#e8ad35"],
            "background_color" => "#edf7f7",
            "label_color" => "#102f42",
            "height" => 140,
            "inner_radius" => 0.58
          }
        }
      ]
    }

    assert {:ok, document, %{pages: 1}} = Declarative.render(source)
    pdf = PaperForge.to_binary(document)
    assert pdf =~ " c"
    assert pdf =~ "0.058824 0.560784 0.513725 rg"
    assert pdf =~ "0.929412 0.968627 0.968627 rg"
    assert pdf =~ "0.062745 0.184314 0.258824 rg"
  end

  test "renders declarative rich text with bold inline runs" do
    source = %{
      "version" => "1",
      "document" => %{"compress" => false},
      "blocks" => [
        %{
          "type" => "rich_text",
          "content" => [
            %{"text" => "Finding. ", "options" => %{"weight" => "bold"}},
            %{"text" => "Structured run. "},
            "The measured response remained stable."
          ]
        }
      ]
    }

    assert {:ok, document, %{pages: 1}} = Declarative.render(source)
    assert PaperForge.to_binary(document) =~ "/BaseFont /Helvetica-Bold"
  end

  test "keeps paragraphs regular unless weight is explicitly bold" do
    regular = %{
      "version" => "1",
      "document" => %{"compress" => false},
      "blocks" => [%{"type" => "paragraph", "text" => "Regular research paragraph"}]
    }

    assert {:ok, regular_document, _report} = Declarative.render(regular)
    regular_pdf = PaperForge.to_binary(regular_document)
    assert regular_pdf =~ "/BaseFont /Helvetica"
    refute regular_pdf =~ "/BaseFont /Helvetica-Bold"

    bold = put_in(regular, ["blocks", Access.at(0), "options"], %{"weight" => "bold"})
    assert {:ok, bold_document, _report} = Declarative.render(bold)
    assert PaperForge.to_binary(bold_document) =~ "/BaseFont /Helvetica-Bold"
  end

  test "declarative columns preserve typography and column_gap" do
    source = %{
      "version" => "1",
      "document" => %{"compress" => false},
      "blocks" => [
        %{
          "type" => "columns",
          "count" => 2,
          "paragraphs" => ["First column", "Second column"],
          "options" => %{
            "column_gap" => 36,
            "weight" => "bold",
            "color" => "#176b87",
            "align" => "right"
          }
        }
      ]
    }

    assert {:ok, compiled} = Declarative.compile(source)
    [block] = compiled.flow.blocks
    assert block.options[:column_gap] == 36

    assert {:ok, document, _report} = Declarative.render(source)
    pdf = PaperForge.to_binary(document)
    assert pdf =~ "/BaseFont /Helvetica-Bold"
    assert pdf =~ "0.090196 0.419608 0.529412 rg"
  end
end
