defmodule PaperForge.Declarative14Test do
  use ExUnit.Case, async: true

  alias PaperForge.Declarative

  test "renders scientific blocks, annotations, and AcroForms from one template" do
    template = %{
      "version" => "1",
      "document" => %{"compress" => false},
      "layout_options" => %{"size" => [400, 520], "margins" => 36},
      "forms" => [
        %{
          "type" => "text",
          "name" => "reviewer",
          "page" => 1,
          "rect" => [180, 50, 340, 76],
          "value" => "Ada",
          "tooltip" => "Reviewer name",
          "border_radius" => 5,
          "border_width" => 0.75,
          "border_color" => "0.65 0.72 0.75"
        },
        %{
          "type" => "radio",
          "name" => "decision",
          "value" => "approve",
          "choices" => [
            %{"page" => 1, "rect" => [180, 90, 198, 108], "value" => "approve"},
            %{"page" => 1, "rect" => [220, 90, 238, 108], "value" => "revise"}
          ]
        }
      ],
      "blocks" => [
        %{"type" => "heading", "text" => "Scientific review"},
        %{"type" => "paragraph", "text" => "Automatically numbered result"},
        %{
          "type" => "equation",
          "ast" => %{
            "fraction" => %{
              "numerator" => %{"symbol" => "1"},
              "denominator" => %{"symbol" => "2"}
            }
          }
        },
        %{"type" => "equation_reference", "number" => 1},
        %{"type" => "footnote", "content" => "Measured with the native Math AST."},
        %{
          "type" => "bibliography",
          "entries" => [
            %{
              "author" => "PaperForge Contributors",
              "title" => "Scientific authoring",
              "year" => 2026
            }
          ]
        },
        %{
          "type" => "annotation",
          "annotation_type" => "stamp",
          "content" => "Reviewed",
          "options" => %{
            "x" => 280,
            "y" => 30,
            "width" => 80,
            "height" => 24,
            "name" => "Approved"
          }
        }
      ]
    }

    assert {:ok, document, report} = Declarative.render(template, %{})
    assert report.pages == 1

    pdf = PaperForge.to_binary(document)
    assert pdf =~ "/AcroForm"
    assert pdf =~ "/Subtype /Stamp"
    assert pdf =~ "Equation 1"
    assert pdf =~ "Scientific authoring"
  end

  test "reports invalid declarative form fields with stable paths" do
    template = %{
      "version" => "1",
      "forms" => [%{"type" => "text", "name" => "broken", "page" => 0, "rect" => [0, 0, 0, 0]}],
      "blocks" => []
    }

    assert {:error, errors} = Declarative.validate(template, %{})
    assert Enum.any?(errors, &(&1.code == :invalid_form_page and &1.path == "$.forms[0].page"))
    assert Enum.any?(errors, &(&1.code == :invalid_form_rect and &1.path == "$.forms[0].rect"))
  end

  test "preserves declarative radio appearance options" do
    template = %{
      "version" => "1",
      "blocks" => [%{"type" => "paragraph", "text" => "Decision"}],
      "forms" => [
        %{
          "type" => "radio",
          "name" => "decision",
          "value" => "approve",
          "tooltip" => "Review decision",
          "background_color" => "0.95 0.98 0.97",
          "border_color" => "0.05 0.55 0.45",
          "border_width" => 0.8,
          "border_radius" => 3,
          "check_color" => "0.05 0.55 0.45",
          "check_width" => 1.2,
          "choices" => [
            %{"page" => 1, "rect" => [40, 40, 54, 54], "value" => "approve"},
            %{"page" => 1, "rect" => [70, 40, 84, 54], "value" => "revise"}
          ]
        }
      ]
    }

    assert {:ok, compiled} = Declarative.compile(template)
    [radio] = compiled.forms
    assert radio.options[:tooltip] == "Review decision"
    assert radio.options[:border_radius] == 3
    assert radio.options[:check_width] == 1.2

    assert {:ok, document, _report} = Declarative.render(template)
    pdf = PaperForge.to_binary(document)
    assert pdf =~ "Review decision"
    assert pdf =~ "/FT /Btn"
  end

  test "renders note and highlight annotations from declarative blocks" do
    template = %{
      "version" => "1",
      "blocks" => [
        %{"type" => "paragraph", "text" => "Review annotations"},
        %{
          "type" => "annotation",
          "annotation_type" => "note",
          "content" => "Check the derivation",
          "options" => %{"x" => 40, "y" => 80, "width" => 18, "height" => 18}
        },
        %{
          "type" => "annotation",
          "annotation_type" => "highlight",
          "content" => "Important result",
          "options" => %{"x" => 70, "y" => 80, "width" => 120, "height" => 16}
        }
      ]
    }

    assert {:ok, document, _report} = Declarative.render(template)
    pdf = PaperForge.to_binary(document)
    assert pdf =~ "/Subtype /Text"
    assert pdf =~ "/Subtype /Highlight"
    assert pdf =~ "Check the derivation"
    assert pdf =~ "Important result"
  end

  test "renders every supported AcroForm field type declaratively" do
    fields = [
      %{
        "type" => "text",
        "name" => "name",
        "page" => 1,
        "rect" => [20, 40, 140, 60],
        "origin" => "top_left"
      },
      %{
        "type" => "checkbox",
        "name" => "accepted",
        "page" => 1,
        "rect" => [20, 70, 34, 84],
        "value" => true
      },
      %{
        "type" => "button",
        "name" => "submit",
        "page" => 1,
        "rect" => [50, 70, 110, 90],
        "value" => "Submit"
      },
      %{
        "type" => "list",
        "name" => "priority",
        "page" => 1,
        "rect" => [20, 100, 140, 145],
        "options" => ["Low", "High"],
        "value" => "High"
      },
      %{
        "type" => "combo",
        "name" => "region",
        "page" => 1,
        "rect" => [20, 155, 140, 177],
        "options" => ["North", "South"]
      },
      %{
        "type" => "signature",
        "name" => "approval_signature",
        "page" => 1,
        "rect" => [20, 190, 180, 225]
      },
      %{
        "type" => "radio",
        "name" => "decision",
        "choices" => [
          %{"page" => 1, "rect" => [20, 240, 34, 254], "value" => "yes"},
          %{"page" => 1, "rect" => [50, 240, 64, 254], "value" => "no"}
        ]
      }
    ]

    template = %{
      "version" => "1",
      "layout_options" => %{"size" => [300, 360], "margins" => 20},
      "blocks" => [%{"type" => "paragraph", "text" => "Complete form"}],
      "forms" => fields
    }

    assert {:ok, document, _report} = Declarative.render(template)
    pdf = PaperForge.to_binary(document)
    assert pdf =~ "/AcroForm"
    assert pdf =~ "/FT /Tx"
    assert pdf =~ "/FT /Btn"
    assert pdf =~ "/FT /Ch"
    assert pdf =~ "/FT /Sig"
    assert pdf =~ "/Rect [20 300 140 320]"
    Enum.each(fields, &assert(pdf =~ &1["name"]))
  end

  test "rejects unknown declarative form origins" do
    template = %{
      "version" => "1",
      "blocks" => [],
      "forms" => [
        %{
          "type" => "text",
          "name" => "reviewer",
          "page" => 1,
          "rect" => [20, 40, 140, 60],
          "origin" => "center"
        }
      ]
    }

    assert {:error, errors} = Declarative.validate(template)
    assert Enum.any?(errors, &(&1.code == :invalid_form_origin))
  end
end
