defmodule PaperForge.ProtectionTest do
  use ExUnit.Case, async: true

  alias PaperForge.Document
  alias PaperForge.Page
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

    assert {:ok, %{attachments: 1, attachment_bytes: 7}} = Protection.audit(document)

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

  defp document do
    PaperForge.new(compress: false)
    |> PaperForge.add_page(fn page -> Page.text(page, "Protected", x: 50, y: 700) end)
  end
end
