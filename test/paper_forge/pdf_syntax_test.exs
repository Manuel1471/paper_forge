defmodule PaperForge.PDF.SyntaxTest do
  use ExUnit.Case, async: true
  alias PaperForge.PDF.Syntax
  alias PaperForge.Reference

  test "reads escaped names, binary strings, octal escapes and continued lines" do
    assert {{:name, "A B"}, " tail"} = Syntax.value("/A#20B tail")

    assert {"a(b)c\n\r\t\b\f\xFFnext\nline", " tail"} =
             Syntax.value("(a\\(b\\)c\\n\\r\\t\\b\\f\\377\\\r\nnext\r\nline) tail")

    assert {{:hex_string, <<0xAB, 0xC0>>}, ""} = Syntax.value("<a b c>")
  end

  test "numbers retain integer precision and accept PDF decimal syntax" do
    assert {9_007_199_254_740_993, ""} = Syntax.value("9007199254740993")
    assert {0.5, ""} = Syntax.value("+.5")
    assert {-0.5, ""} = Syntax.value("-.5")
    assert {4.0, ""} = Syntax.value("4.")
    assert {%Reference{object_id: 22, generation: 3}, ""} = Syntax.value("22 % note\n3 R")
    assert {:pdf_error, {:unsupported_pdf_token, "1e3"}} = catch_throw(Syntax.value("1e3"))
  end

  test "limits syntax nesting without counting brackets in binary strings" do
    assert {"<<<<[[[[", ""} = Syntax.value("(<<<<[[[[)", 2)
    assert {%{"A" => [nil, true, false]}, ""} = Syntax.value("<< /A [null true false] >>")
    assert {:pdf_error, {:max_depth_exceeded, 2}} = catch_throw(Syntax.value("[[[0]]]", 2))
    assert {:pdf_error, :invalid_pdf_value} = catch_throw(Syntax.value("]"))
    assert {:pdf_error, :unterminated_pdf_string} = catch_throw(Syntax.value("(unfinished"))
  end
end
