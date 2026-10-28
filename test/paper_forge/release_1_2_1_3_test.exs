defmodule PaperForge.Release12And13Test do
  use ExUnit.Case, async: true
  alias PaperForge.Declarative
  alias PaperForge.Document
  alias PaperForge.PDF.Parser
  alias PaperForge.Protection

  defp template(tokens) do
    %{
      "version" => "1",
      "document" => %{"compress" => false},
      "design_system" => %{"tokens" => tokens},
      "blocks" => [
        %{"type" => "paragraph", "text" => "Hello", "options" => %{"size" => "$type.body"}}
      ]
    }
  end

  test "token aliases resolve recursively and application themes override template defaults" do
    source = template(%{"base" => 11, "type" => %{"body" => "$base"}})

    source =
      source
      |> Map.put("theme", "compact")
      |> put_in(["design_system", "themes"], %{
        "compact" => %{"tokens" => %{"base" => 9}},
        "comfortable" => %{"tokens" => %{"base" => 13}}
      })

    for {options, size} <- [{[], 9}, {[theme: "comfortable"], 13}, {[theme: nil], 11}] do
      assert {:ok, document, _} = Declarative.render(source, %{}, options)
      pdf = PaperForge.to_binary(%{document | compress: false})
      assert pdf =~ "#{size} Tf"
    end
  end

  test "missing and cyclic tokens fail during compilation" do
    for tokens <- [%{}, %{"type" => %{"body" => "$other"}, "other" => "$type.body"}] do
      assert {:error, errors} = Declarative.compile(template(tokens))
      assert Enum.any?(errors, &String.contains?(&1.message, "token"))
    end
  end

  test "watermark presentation accepts theme tokens without interpreting literal text" do
    source =
      template(%{"type" => %{"body" => 11}, "mark" => %{"size" => 22, "color" => "#247E83"}})

    source =
      Map.put(source, "protection", %{
        "watermark" => %{
          "text" => "$100",
          "size" => "$mark.size",
          "color" => "$mark.color",
          "fit" => true
        }
      })

    assert {:ok, compiled} = Declarative.compile(source)
    assert compiled.protection[:watermark][:size] == 22
    assert compiled.protection[:watermark][:text] == "$100"
    assert {:ok, _, _} = Declarative.render(source)
  end

  test "protection preserves third-party PieceInfo and detects its modification" do
    doc = PaperForge.new() |> PaperForge.add_page(fn page -> page end)

    doc =
      Document.update_object(doc, doc.root_reference, fn catalog ->
        Map.put(catalog, "PieceInfo", %{"OtherApp" => %{"Private" => "original"}})
      end)

    protected = Protection.apply(doc, [])
    catalog = Document.fetch_object!(protected, protected.root_reference).value
    assert catalog["PieceInfo"]["OtherApp"]["Private"] == "original"
    assert :ok = Protection.verify_fingerprint(protected)

    changed =
      Document.update_object(protected, protected.root_reference, fn catalog ->
        put_in(catalog, ["PieceInfo", "OtherApp", "Private"], "modified")
      end)

    assert {:error, :modified} = Protection.verify_fingerprint(changed)

    malformed =
      Document.update_object(protected, protected.root_reference, fn catalog ->
        put_in(catalog, ["PieceInfo", "PaperForge", "Private", "Fingerprint"], 123)
      end)

    assert {:error, :modified} = Protection.verify_fingerprint(malformed)
  end

  test "fingerprints survive serialization, compression and Unicode metadata" do
    for compress <- [true, false] do
      doc =
        PaperForge.new(compress: compress)
        |> PaperForge.add_page(fn page ->
          PaperForge.Page.text(page, "Unchanged", x: 20, y: 20)
        end)

      {doc, info} =
        Document.add_object(doc, %{
          "Title" => {:hex_string, <<254, 255, 0, 241>>}
        })

      doc = Protection.apply(%{doc | info_reference: info}, [])
      assert {:ok, reopened} = Parser.parse(PaperForge.to_binary(doc))
      assert :ok = Protection.verify_fingerprint(reopened)
    end
  end
end
