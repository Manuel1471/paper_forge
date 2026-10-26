defmodule PaperForge.Release14RegressionTest do
  use ExUnit.Case, async: true
  alias PaperForge.{AcroForm, Declarative, Document, Import, Math, Page, Scientific}

  alias PaperForge.PDF.Graph

  test "named declarative templates and styles resolve even when their names exist as atoms" do
    template = %{
      "version" => "1",
      "page_templates" => %{"body" => %{"size" => [400, 500], "margins" => 40}},
      "layout_options" => %{"template" => "body"},
      "design_system" => %{"styles" => %{"title" => %{"size" => 32}}},
      "blocks" => [
        %{"type" => "paragraph", "text" => "Styled", "options" => %{"style" => "title"}}
      ]
    }

    assert {:ok, document, _} = Declarative.render(template)
    {:ok, [page]} = Graph.pages(document)
    assert page.dictionary["MediaBox"] == [0, 0, 400, 500]
    assert PaperForge.to_binary(document) =~ "%PDF"
    assert {:ok, compiled} = Declarative.compile(template)
    assert compiled.styles["title"][:size] == 32
    assert compiled.page_templates["body"][:size] == {400, 500}
  end

  test "SVG anchors use the width of the rendered bold glyphs" do
    page =
      PaperForge.SVG.render(
        Page.new(),
        "<svg viewBox='0 0 200 50'><text x='100' y='25' font-size='20' font-weight='bold' text-anchor='middle'>WWii</text></svg>",
        x: 0,
        y: 0,
        width: 200,
        height: 50
      )

    [{:text, "WWii", options}] = page.operations
    expected = 100 - PaperForge.TextMetrics.width("WWii", font: :helvetica_bold, size: 20) / 2
    assert_in_delta options[:x], expected, 0.0001
  end

  test "math alignment uses measured width within the actual layout column" do
    ast = Math.symbol("x")
    flow = PaperForge.Flow.new() |> PaperForge.Flow.math(ast, align: :center, size: 20)
    [block] = flow.blocks
    page = block.content.(Page.new(), %{block_x: 40, block_y: 100, block_width: 200})
    [{:text, "x", options}] = page.operations
    {width, _} = Math.measure(ast, size: 20)
    assert_in_delta options[:x], 40 + (200 - width) / 2, 0.0001
  end

  test "declarative equation references follow custom destinations" do
    template = %{
      "version" => "1",
      "blocks" => [
        %{
          "type" => "equation",
          "ast" => %{"symbol" => "x"},
          "options" => %{"destination" => "custom"}
        },
        %{"type" => "equation_reference", "number" => 1}
      ]
    }

    assert {:ok, compiled} = Declarative.compile(template)
    assert Enum.find(compiled.flow.blocks, &(&1.type == :reference)).content == "custom"
    assert {:ok, _, _} = Declarative.render(template)
  end

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
    {_, simple_height} = Math.measure(Math.symbol("next"), size: 16 * 0.8)
    assert height >= fraction_height + simple_height
    assert height < 2 * (fraction_height + 4) + 8
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
    assert width >= 16 * 1.55 + bw + dw
    assert height >= bh + 16 * 0.55
  end
end
