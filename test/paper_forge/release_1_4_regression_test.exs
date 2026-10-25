defmodule PaperForge.Release14RegressionTest do
  use ExUnit.Case, async: true
  alias PaperForge.{AcroForm, Declarative, Document, Import, Math, Page, Scientific}

  test "HTML preserves UTF-8 and inline SVG instead of silently dropping artwork" do
    html =
      ~s(<h1>Información de España</h1><p>Niñez € “sí”</p><svg width="100" height="30"><text x="2" y="20">México</text></svg>)

    assert {:ok, flow} = Import.html(html)

    assert Enum.any?(
             flow.blocks,
             &(&1.type == :heading and &1.content == "Información de España")
           )

    assert Enum.any?(flow.blocks, &(&1.type == :svg))
    template = %{"version" => "1", "blocks" => [%{"type" => "html", "content" => html}]}
    assert {:ok, document, _} = Declarative.render(template)
    assert PaperForge.to_binary(document) =~ "%PDF"
  end

  test "scientific references retain a custom equation destination" do
    flow =
      Scientific.new()
      |> Scientific.equation(Math.symbol("x"), destination: "custom-equation")
      |> Scientific.equation_reference(1, size: 11)
      |> Scientific.to_flow()

    reference = Enum.find(flow.blocks, &(&1.type == :reference))
    assert reference.content == "custom-equation"
    assert reference.options[:size] == 11
  end

  test "declarative fields can use a registered font for non-Latin values" do
    template = %{
      "version" => "1",
      "fonts" => %{"review" => %{"source" => "fixture"}},
      "blocks" => [%{"type" => "paragraph", "text" => "Form"}],
      "forms" => [
        %{
          "type" => "text",
          "name" => "日本語",
          "font" => "review",
          "page" => 1,
          "rect" => [20, 20, 300, 50],
          "value" => "Ω Ж"
        }
      ]
    }

    assert {:ok, doc, _} =
             Declarative.render(template, %{},
               font_sources: %{"fixture" => File.read!("test/fixtures/fonts/SFNSMono.ttf")}
             )

    assert AcroForm.export_data(doc) == %{"日本語" => "Ω Ж"}
    assert PaperForge.to_binary(doc) =~ "/ToUnicode"
  end

  test "editing and flattening explicitly reject direct XFA forms" do
    document = PaperForge.new() |> PaperForge.add_page(Page.new())

    document =
      Document.update_object(
        document,
        document.root_reference,
        &Map.put(&1, "AcroForm", %{"Fields" => [], "XFA" => "unsupported"})
      )

    assert_raise ArgumentError, ~r/XFA/, fn -> AcroForm.flatten(document) end
    assert_raise ArgumentError, ~r/XFA/, fn -> AcroForm.import_data(document, %{}) end

    assert_raise ArgumentError, ~r/XFA/, fn ->
      AcroForm.add_field(document, 1, :text, "name", rect: [0, 0, 20, 20])
    end
  end

  test "matrix rows reserve nested fraction heights and empty rows remain renderable" do
    fraction = Math.fraction(Math.symbol("top"), Math.symbol("bottom"))
    matrix = Math.matrix([[fraction], [Math.symbol("next")]])
    {_width, height} = Math.measure(matrix, size: 16)
    {_width, fraction_height} = Math.measure(fraction, size: 16 * 0.8)
    assert height >= 2 * (fraction_height + 4) + 8
    page = Math.render(Page.new(origin: :top_left), matrix, x: 20, y: 20, size: 16)
    assert is_binary(Page.content(page))
    empty = Math.render(Page.new(origin: :top_left), Math.matrix([[]]), x: 20, y: 20)
    assert is_binary(Page.content(empty))
  end

  test "integrals measure wide differentials and tall bodies" do
    body = Math.fraction(Math.symbol("A"), Math.fraction(Math.symbol("B"), Math.symbol("C")))
    expression = Math.integral(nil, nil, body, "WWW")
    {bw, bh} = Math.measure(body, size: 16)
    {dw, _} = Math.measure(Math.symbol(" dWWW"), size: 16)
    {width, height} = Math.measure(expression, size: 16)
    assert width >= 32 + bw + dw + 2
    assert height >= bh + 16 * 0.55
  end
end
