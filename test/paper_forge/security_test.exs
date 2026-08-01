defmodule PaperForge.SecurityTest do
  use ExUnit.Case, async: true

  alias PaperForge.Page

  @security [
    user_password: "reader-secret",
    owner_password: "owner-secret",
    permissions: [print: :high_resolution, copy: false, modify: false, extract: false]
  ]

  test "writes an AES-256 Standard Security Handler dictionary" do
    pdf = encrypted_pdf()

    assert pdf =~ "/Filter /Standard"
    assert pdf =~ "/V 5"
    assert pdf =~ "/R 6"
    assert pdf =~ "/CFM /AESV3"
    assert pdf =~ "/Length 256"
    assert pdf =~ "/Encrypt "
    assert pdf =~ "/ID ["
    refute pdf =~ "PaperForge confidential payload"
  end

  test "produces deterministic encrypted output with an injected random source" do
    random = fn size -> :binary.copy(<<size>>, size) end
    security = Keyword.put(@security, :random, random)

    first = PaperForge.to_binary(document(), security: security)
    second = PaperForge.to_binary(document(), security: security)

    assert first == second
  end

  test "uses fresh keys and initialization vectors by default" do
    refute encrypted_pdf() == encrypted_pdf()
  end

  test "leaves XMP metadata streams readable when metadata encryption is disabled" do
    compliant = PaperForge.comply(document(), profiles: [:pdf_ua_1], language: "en-US")

    pdf =
      PaperForge.to_binary(compliant,
        security: Keyword.put(@security, :encrypt_metadata, false)
      )

    assert pdf =~ "/EncryptMetadata false"
    assert pdf =~ "pdfuaid:part"
    refute pdf =~ "PaperForge confidential payload"
  end

  test "requires an owner password and rejects unsupported algorithms" do
    assert_raise ArgumentError, ~r/missing_password.*owner_password/, fn ->
      PaperForge.to_binary(document(), security: [user_password: "reader"])
    end

    assert_raise ArgumentError, ~r/unsupported_algorithm/, fn ->
      PaperForge.to_binary(document(),
        security: [algorithm: :rc4, owner_password: "owner"]
      )
    end
  end

  test "rejects passwords longer than the PDF 2.0 limit" do
    assert_raise ArgumentError, ~r/password_too_long.*user_password/, fn ->
      PaperForge.to_binary(document(),
        security: [user_password: String.duplicate("x", 128), owner_password: "owner"]
      )
    end
  end

  test "pdfinfo opens with the user password and enforces permissions when available" do
    case System.find_executable("pdfinfo") do
      nil ->
        :ok

      executable ->
        path = Path.join(System.tmp_dir!(), "paper_forge_aes_#{System.unique_integer()}.pdf")
        :ok = PaperForge.write(document(), path, security: @security)

        {without_password, failure_status} =
          System.cmd(executable, [path], stderr_to_stdout: true)

        assert failure_status != 0
        assert without_password =~ "password"

        {output, status} =
          System.cmd(executable, ["-upw", "reader-secret", path], stderr_to_stdout: true)

        assert status == 0, output
        assert output =~ "Encrypted:"
        assert output =~ "print:yes"
        assert output =~ "copy:no"
        assert output =~ "change:no"
        assert output =~ "algorithm:AES-256"
    end
  end

  defp encrypted_pdf, do: PaperForge.to_binary(document(), security: @security)

  defp document do
    PaperForge.new(compress: false)
    |> PaperForge.metadata(title: "Protected report")
    |> PaperForge.add_page(fn page ->
      Page.text(page, "PaperForge confidential payload", x: 72, y: 720)
    end)
  end
end
