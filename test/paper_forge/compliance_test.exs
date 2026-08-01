defmodule PaperForge.ComplianceTest do
  use ExUnit.Case, async: true

  alias PaperForge.Compliance
  alias PaperForge.Document
  alias PaperForge.Page

  test "builds tagged PDF/UA structure, language, reading order, and XMP" do
    document =
      document()
      |> PaperForge.comply(profiles: [:pdf_ua_1], language: "en-US")

    assert {:ok, report} = Compliance.validate(document, profiles: [:pdf_ua_1])
    assert report.tagged
    assert report.language == "en-US"

    pdf = PaperForge.to_binary(document)
    assert pdf =~ "/StructTreeRoot"
    assert pdf =~ "/StructParents 0"
    assert pdf =~ "/MarkInfo <<"
    assert pdf =~ "/Marked true"
    assert pdf =~ "/P <</MCID 0>> BDC"
    assert pdf =~ "pdfuaid:part"
  end

  test "builds PDF/A output intent and profile metadata from an ICC binary" do
    document =
      document()
      |> PaperForge.comply(profiles: [:pdf_a_2b], icc_profile: rgb_icc())

    assert {:ok, report} = Compliance.validate(document, profiles: [:pdf_a_2b])
    assert report.output_intent

    pdf = PaperForge.to_binary(document)
    assert pdf =~ "/Type /OutputIntent"
    assert pdf =~ "/S /GTS_PDFA1"
    assert pdf =~ "pdfaid:part"
  end

  test "supports combined archival and accessibility preparation" do
    document =
      document()
      |> PaperForge.comply(
        profiles: [:pdf_a_3b, :pdf_ua_1],
        language: "en-MX",
        icc_profile: rgb_icc()
      )

    assert {:ok, %{profiles: [:pdf_a_3b, :pdf_ua_1]}} =
             Compliance.validate(document, profiles: [:pdf_a_3b, :pdf_ua_1])
  end

  test "reports missing profile requirements with paths" do
    assert {:error, issues} = Compliance.validate(document(), profiles: [:pdf_ua_1])

    assert Enum.any?(issues, &(&1.code == :xmp_missing and &1.path == "catalog.Metadata"))
    assert Enum.any?(issues, &(&1.code == :structure_tree_missing))
  end

  test "rejects missing or malformed ICC profiles and PDF/A encryption" do
    assert_raise ArgumentError, ~r/requires :icc_profile/, fn ->
      PaperForge.comply(document(), profiles: [:pdf_a_2b])
    end

    assert_raise ArgumentError, ~r/invalid ICC profile signature/, fn ->
      PaperForge.comply(document(), profiles: [:pdf_a_2b], icc_profile: :binary.copy(<<0>>, 128))
    end

    prepared = PaperForge.comply(document(), profiles: [:pdf_a_2b], icc_profile: rgb_icc())

    assert {:error, issues} =
             Compliance.validate(prepared,
               profiles: [:pdf_a_2b],
               security: [owner_password: "owner"]
             )

    assert Enum.any?(issues, &(&1.code == :encryption_forbidden))
  end

  test "alternate text is attached to image XObjects" do
    image = jpeg(2, 2, 3)

    document =
      PaperForge.add_page(document(), fn page ->
        Page.image(page, image, x: 20, y: 20, width: 20)
      end)

    image_ref = document.image_registry.images |> Map.values() |> hd() |> Map.fetch!(:reference)
    document = Compliance.alternate_text(document, image_ref, "A two-pixel sample image")

    assert Document.fetch_object!(document, image_ref).value.dictionary["Alt"] ==
             "A two-pixel sample image"
  end

  defp document do
    PaperForge.new(compress: false)
    |> PaperForge.metadata(title: "Accessible annual report", author: "PaperForge")
    |> PaperForge.add_page(fn page -> Page.text(page, "Readable content", x: 50, y: 700) end)
  end

  defp rgb_icc do
    header = :binary.copy(<<0>>, 128)
    header = put_binary(header, 16, "RGB ")
    put_binary(header, 36, "acsp")
  end

  defp put_binary(binary, offset, replacement) do
    prefix = binary_part(binary, 0, offset)

    suffix =
      binary_part(
        binary,
        offset + byte_size(replacement),
        byte_size(binary) - offset - byte_size(replacement)
      )

    prefix <> replacement <> suffix
  end

  defp jpeg(width, height, components) do
    component_data = for component <- 1..components, into: <<>>, do: <<component, 0x11, 0>>
    segment_length = 8 + components * 3

    <<0xFF, 0xD8, 0xFF, 0xC0, segment_length::16-big, 8, height::16-big, width::16-big,
      components, component_data::binary, 0xFF, 0xD9>>
  end
end
