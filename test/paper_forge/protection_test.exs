defmodule PaperForge.ProtectionTest do
  use ExUnit.Case, async: true

  alias PaperForge.Document
  alias PaperForge.Page
  alias PaperForge.PDF.Graph
  alias PaperForge.Protection

  test "adds a watermark stream and resources to every page" do
    document =
      PaperForge.new(compress: false)
      |> PaperForge.add_page(fn page -> Page.text(page, "First", x: 40, y: 700) end)
      |> PaperForge.add_page(fn page -> Page.text(page, "Second", x: 40, y: 700) end)
      |> PaperForge.protect(watermark: [text: "CONFIDENTIAL", opacity: 0.2])

    pdf = PaperForge.to_binary(document)

    assert length(Regex.scan(~r/\/PFWatermarkGS gs/, pdf)) == 2
    assert pdf =~ "/BaseFont /Helvetica-Bold"
    assert pdf =~ "/ca 0.2"
    assert pdf =~ "(CONFIDENTIAL) Tj"
  end

  test "stamps and verifies a stable content fingerprint" do
    protected = PaperForge.protect(document(), identifier: "urn:example:report-42")

    assert :ok = Protection.verify_fingerprint(protected)
    assert PaperForge.to_binary(protected) =~ "urn:example:report-42"

    [page_ref] = Document.fetch_object!(protected, protected.pages_reference).value["Kids"]

    modified =
      Document.update_object(protected, page_ref, fn page ->
        Map.put(page, "Rotate", 90)
      end)

    assert {:error, :modified} = Protection.verify_fingerprint(modified)
  end

  test "rejects disallowed URI schemes and hosts" do
    document =
      PaperForge.new()
      |> PaperForge.add_page(fn page ->
        Page.link(page, "http://untrusted.example/report", x: 10, y: 10, width: 80, height: 20)
      end)

    assert {:error, issues} =
             Protection.audit(document,
               allowed_uri_schemes: ["https"],
               allowed_hosts: ["paperforge.dev"]
             )

    assert Enum.any?(issues, &(&1.code == :uri_scheme_denied))
  end

  test "enforces attachment count, size, MIME, and allow policies" do
    document = PaperForge.attach(document(), "source.csv", "a,b\n1,2", mime: "text/csv")

    assert {:ok, %{attachments: 1, attachment_bytes: 7}} =
             Protection.audit(document, allowed_attachment_mimes: ["text/csv"])

    assert {:error, issues} =
             Protection.audit(document,
               allow_attachments: false,
               max_attachment_bytes: 3,
               allowed_attachment_mimes: ["application/pdf"]
             )

    codes = MapSet.new(issues, & &1.code)

    assert MapSet.subset?(
             MapSet.new([:attachments_denied, :attachment_too_large, :attachment_mime_denied]),
             codes
           )
  end

  test "raises before serialization when a protection policy fails" do
    assert_raise ArgumentError, ~r/attachments are disabled/, fn ->
      document()
      |> PaperForge.attach("private.txt", "secret")
      |> PaperForge.protect(policy: [allow_attachments: false])
    end
  end

  test "centers using actual font metrics and retains distinct watermark resources" do
    text = "WWW iii"
    width = PaperForge.TextMetrics.width(text, font: :helvetica_bold, size: 20)
    doc = Protection.watermark(document(), text: text, angle: 0, size: 20)
    [page] = Graph.pages!(doc)
    stream = Document.fetch_object!(doc, List.last(page.dictionary["Contents"])).value
    [_, x, y] = Regex.run(~r/1 0 -?0 1 ([\d.]+) ([\d.]+) Tm/, stream.data)
    [x0, y0, x1, y1] = page.dictionary["MediaBox"]
    assert_in_delta String.to_float(x) + width / 2, (x0 + x1) / 2, 0.001
    assert_in_delta String.to_float(y) + 20 * 0.718 / 2, (y0 + y1) / 2, 0.001

    twice = Protection.watermark(doc, text: "SECOND", opacity: 0.5)
    [page] = Graph.pages!(twice)
    assert map_size(page.dictionary["Resources"]["ExtGState"]) == 2

    assert page.dictionary["Resources"]["Font"]["PFWatermark"] !=
             page.dictionary["Resources"]["Font"]["PFWatermark_"]
  end

  test "fits long watermarks and rejects unusable dimensions" do
    doc = Protection.watermark(document(), text: String.duplicate("W", 100), size: 54)
    [page] = Graph.pages!(doc)
    stream = Document.fetch_object!(doc, List.last(page.dictionary["Contents"])).value
    [_, size] = Regex.run(~r/PFWatermark ([\d.]+) Tf/, stream.data)
    assert String.to_float(size) < 10

    for options <- [[size: 0], [margin: -1], [opacity: "bad"], [fit: :yes], [margin: 1000]] do
      assert_raise ArgumentError, fn ->
        Protection.watermark(document(), [text: "DRAFT"] ++ options)
      end
    end
  end

  test "accepts inherited indirect resources and offset page boxes" do
    doc = document()
    [page] = Graph.pages!(doc)
    {doc, resources} = Document.add_object(doc, page.dictionary["Resources"])

    doc =
      Document.update_object(doc, doc.pages_reference, fn tree ->
        Map.put(tree, "Resources", resources)
      end)

    doc =
      Document.update_object(doc, page.reference, fn value ->
        value |> Map.delete("Resources") |> Map.put("MediaBox", [100, 200, 500, 800])
      end)

    doc = Protection.watermark(doc, text: "TEST", angle: 0, size: 20)
    [result] = Graph.pages!(doc)
    assert result.dictionary["Resources"]["Font"]["PFWatermark"]
    stream = Document.fetch_object!(doc, List.last(result.dictionary["Contents"])).value
    [_, x, y] = Regex.run(~r/1 0 -?0 1 ([\d.]+) ([\d.]+) Tm/, stream.data)
    width = PaperForge.TextMetrics.width("TEST", font: :helvetica_bold, size: 20)
    assert_in_delta String.to_float(x) + width / 2, 300, 0.001
    assert_in_delta String.to_float(y) + 7.18, 500, 0.001
  end

  defp document do
    PaperForge.new(compress: false)
    |> PaperForge.add_page(fn page -> Page.text(page, "Protected", x: 50, y: 700) end)
  end
end
