defmodule PaperForge.AcroFormTest do
  use ExUnit.Case, async: true

  alias PaperForge.{AcroForm, Page, Stream}

  test "creates standard fields, radio groups, calculations, and data round trips" do
    document = PaperForge.new(compress: false) |> PaperForge.add_page(Page.new())

    document =
      document
      |> AcroForm.add_field(1, :text, "customer", rect: [40, 700, 220, 724], value: "Ada")
      |> AcroForm.add_field(1, :checkbox, "approved", rect: [40, 660, 58, 678], value: true)
      |> AcroForm.add_field(1, :combo, "country",
        rect: [80, 620, 220, 644],
        options: ["Mexico", "Canada"],
        value: "Mexico"
      )
      |> AcroForm.add_field(1, :text, "total",
        rect: [80, 580, 220, 604],
        calculation: {:sum, ["subtotal", "tax"]}
      )
      |> AcroForm.add_field(1, :signature, "approval_signature", rect: [40, 520, 220, 560])
      |> AcroForm.add_radio_group(
        "plan",
        [
          [page: 1, rect: [40, 480, 58, 498], value: "basic"],
          [page: 1, rect: [80, 480, 98, 498], value: "pro"]
        ],
        value: "pro"
      )

    assert AcroForm.validate(document) == :ok
    assert AcroForm.export_data(document)["plan"] == "pro"
    assert AcroForm.export_data(document)["approved"] == "Yes"

    updated = AcroForm.import_data(document, customer: "Grace", plan: "basic")
    assert AcroForm.export_data(updated)["customer"] == "Grace"
    assert AcroForm.export_data(updated)["plan"] == "basic"

    pdf = PaperForge.to_binary(updated)
    assert pdf =~ "/AcroForm"
    assert pdf =~ "/JavaScript"
    assert pdf =~ "/V /basic"

    flattened = AcroForm.flatten(updated)
    refute PaperForge.to_binary(flattened) =~ "/AcroForm"
  end

  test "supports compact rounded field appearances" do
    document =
      PaperForge.new(compress: false)
      |> PaperForge.add_page(Page.new())
      |> AcroForm.add_field(1, :text, "reviewer",
        rect: [40, 700, 180, 719],
        border_radius: 5,
        border_width: 0.6,
        border_color: "0.65 0.72 0.75"
      )
      |> AcroForm.add_field(1, :checkbox, "reviewed",
        rect: [40, 670, 52, 682],
        value: true,
        border_radius: 3,
        check_color: "0.04 0.56 0.48"
      )

    appearances =
      document.objects
      |> Map.values()
      |> Enum.map(& &1.value)
      |> Enum.filter(&match?(%Stream{}, &1))
      |> Enum.map(&(&1.data |> IO.iodata_to_binary()))

    assert Enum.any?(appearances, &String.contains?(&1, " c h"))
    assert Enum.any?(appearances, &String.contains?(&1, "0.04 0.56 0.48 RG"))
  end

  test "serializes numeric radio values as PDF names" do
    document =
      PaperForge.new(compress: false)
      |> PaperForge.add_page(Page.new())
      |> AcroForm.add_radio_group(
        "rating",
        [
          [page: 1, rect: [40, 480, 58, 498], value: 1],
          [page: 1, rect: [80, 480, 98, 498], value: 2]
        ],
        value: 1
      )

    assert AcroForm.export_data(document)["rating"] == "1"
    assert PaperForge.to_binary(document) =~ "/V /1"
  end

  test "normalizes hexadecimal appearance colors into valid PDF operators" do
    document =
      PaperForge.new(compress: false)
      |> PaperForge.add_page(Page.new())
      |> AcroForm.add_field(1, :text, "reviewer",
        rect: [40, 700, 180, 719],
        background_color: "#ffffff",
        border_color: "#9eb8c4"
      )

    appearances =
      document.objects
      |> Map.values()
      |> Enum.map(& &1.value)
      |> Enum.filter(&match?(%Stream{}, &1))
      |> Enum.map(&(&1.data |> IO.iodata_to_binary()))

    refute Enum.any?(appearances, &String.contains?(&1, "#"))
    assert Enum.any?(appearances, &String.contains?(&1, "1 1 1 rg"))
  end
end
