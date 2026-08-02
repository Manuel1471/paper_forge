defmodule PaperForge.ScientificTest do
  use ExUnit.Case, async: true

  alias PaperForge.{Flow, Math, Scientific}

  test "measures native scientific expressions and builds numbered references" do
    expression =
      Math.row([
        Math.integral(
          Math.symbol("0"),
          Math.symbol("1"),
          Math.superscript(Math.symbol("x"), Math.symbol("2")),
          "x"
        ),
        Math.symbol("="),
        Math.fraction(Math.symbol("1"), Math.symbol("3"))
      ])

    {width, height} = Math.measure(expression, size: 16)
    assert width > 60
    assert height > 16

    scientific =
      Scientific.new()
      |> Scientific.equation(expression)
      |> Scientific.equation_reference(1)

    {scientific, 1} =
      Scientific.cite(scientific, "paper", title: "PaperForge methods", year: 2026)

    flow = scientific |> Scientific.bibliography() |> Scientific.to_flow()

    assert %Flow{} = flow
    assert Enum.any?(flow.blocks, &(&1.type == :reference))
    assert Enum.any?(flow.blocks, &(&1.type == :custom))
  end

  test "fractions reserve readable vertical space around the rule" do
    size = 16
    numerator = Math.symbol("observed - baseline")
    denominator = Math.symbol("variance")
    fraction = Math.fraction(numerator, denominator)

    {_width, numerator_height} = Math.measure(numerator, size: size * 0.82)
    {_width, denominator_height} = Math.measure(denominator, size: size * 0.82)
    {_width, fraction_height} = Math.measure(fraction, size: size)

    expected_gap = size * 0.28

    assert_in_delta fraction_height,
                    numerator_height + denominator_height + expected_gap * 2,
                    0.001
  end

  test "symbol advances use the same builtin font metrics as rendered text" do
    text = "CO"
    size = 12
    {width, _height} = Math.measure(Math.symbol(text), size: size)

    assert_in_delta width,
                    PaperForge.TextMetrics.line_width(text, font: :helvetica, size: size),
                    0.001
  end

  test "integrals reserve a compact operator box with adjacent limits" do
    size = 16
    body = Math.superscript(Math.symbol("psi(t)"), Math.symbol("2"))
    integral = Math.integral(Math.symbol("0"), Math.symbol("tau"), body, "t")
    {width, height} = Math.measure(integral, size: size)
    {body_width, _height} = Math.measure(body, size: size)

    assert width > body_width + 22
    assert width < body_width + 70
    assert_in_delta height, size * 2.55, 0.001
  end

  test "integral limits clear both the operator and expression body" do
    page =
      PaperForge.Page.new(origin: :top_left)
      |> Math.render(
        Math.integral(
          Math.symbol("0"),
          Math.symbol("tau"),
          Math.superscript(Math.symbol("psi(t)"), Math.symbol("2")),
          "t"
        ),
        x: 20,
        y: 20,
        size: 16
      )

    operations = Enum.reverse(page.operations)

    {:path, [{:move_to, operator_tip_x, _} | _], _} =
      Enum.find(operations, &match?({:path, _, _}, &1))

    {:text, "tau", upper_options} = Enum.find(operations, &match?({:text, "tau", _}, &1))
    {:text, "psi(t)", body_options} = Enum.find(operations, &match?({:text, "psi(t)", _}, &1))
    {limit_width, _height} = Math.measure(Math.symbol("tau"), size: 16 * 0.55)

    assert upper_options[:x] >= operator_tip_x + 4
    assert body_options[:x] >= upper_options[:x] + limit_width + 4
  end

  test "roots reserve clearance above superscripted radicands" do
    size = 16
    radicand = Math.superscript(Math.symbol("A"), Math.symbol("2"))
    plain_root = Math.root(Math.symbol("A"))
    scripted_root = Math.root(radicand)
    {_plain_width, plain_height} = Math.measure(plain_root, size: size)
    {_scripted_width, scripted_height} = Math.measure(scripted_root, size: size)

    assert scripted_height > plain_height + size * 0.2

    page =
      PaperForge.Page.new(origin: :top_left)
      |> Math.render(scripted_root, x: 20, y: 20, size: size)

    operations = Enum.reverse(page.operations)

    {:line, bar_options} =
      Enum.find(operations, fn
        {:line, options} -> options[:y1] == options[:y2] and options[:x2] > options[:x1]
        _ -> false
      end)

    {:text, "2", exponent_options} = Enum.find(operations, &match?({:text, "2", _}, &1))
    assert exponent_options[:y] > bar_options[:y1] + 2
  end

  test "matrix cells are centered inside symmetric brackets" do
    page =
      PaperForge.Page.new(origin: :top_left)
      |> Math.render(
        Math.matrix([
          [Math.symbol("0"), Math.symbol("wide"), Math.symbol("0")],
          [Math.symbol("k"), Math.symbol("d"), Math.symbol("k")]
        ]),
        x: 20,
        y: 20,
        size: 16
      )

    operations = Enum.reverse(page.operations)

    verticals =
      Enum.filter(operations, fn
        {:line, options} -> options[:x1] == options[:x2] and options[:y2] > options[:y1]
        _ -> false
      end)

    [{:line, left}, {:line, right}] = verticals
    {:text, "wide", wide_options} = Enum.find(operations, &match?({:text, "wide", _}, &1))
    {wide_width, _height} = Math.measure(Math.symbol("wide"), size: 16 * 0.8)
    matrix_center = (left[:x1] + right[:x1]) / 2
    content_center = wide_options[:x] + wide_width / 2

    assert_in_delta content_center, matrix_center, 0.001
  end
end
