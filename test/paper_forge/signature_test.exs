defmodule PaperForge.SignatureTest do
  use ExUnit.Case, async: true

  alias PaperForge.Signature

  defmodule TestProvider do
    @behaviour PaperForge.Signature.Provider

    def capabilities, do: [:visible, :multiple]
    def sign(pdf, options), do: {:ok, pdf <> Keyword.get(options, :suffix, "-signed")}
    def verify(_pdf, _options), do: {:ok, :test_identity}
  end

  @fixture_dir Path.expand("../fixtures", __DIR__)

  test "uses a configurable provider" do
    assert Signature.capabilities(provider: TestProvider) == [:visible, :multiple]

    assert {:ok, "%PDF-test"} =
             Signature.sign("%PDF", provider: TestProvider, suffix: "-test")

    assert {:ok, :test_identity} = Signature.verify("%PDF", provider: TestProvider)
  end

  test "default provider signs incrementally with PKCS8 and no external executable" do
    document = PaperForge.new(compress: false) |> PaperForge.add_page(fn page -> page end)
    pdf = PaperForge.to_binary(document)

    assert {:ok, signed} =
             Signature.sign(pdf,
               certificate:
                 {:pkcs8,
                  key_path: Path.join(@fixture_dir, "signing_key.pem"),
                  cert_path: Path.join(@fixture_dir, "signing_cert.pem")},
               alg: :PS256,
               reason: "PaperForge test approval",
               location: "Monterrey, Mexico"
             )

    assert String.starts_with?(signed, pdf)
    assert signed =~ "/ByteRange"
    assert signed =~ "/SubFilter /ETSI.CAdES.detached"
    assert signed =~ "PaperForge test approval"
  end

  test "reports unsupported default-provider capabilities explicitly" do
    assert {:error, {:unsupported_capability, :visible}} =
             Signature.sign("%PDF", visible: true)

    assert {:error, {:unsupported_capability, :multiple}} =
             Signature.sign("%PDF", multiple: true)
  end

  test "PKCS12 remains an explicit optional compatibility source" do
    assert {:error, {:bundle_not_found, "missing.p12"}} =
             Signature.sign("%PDF",
               certificate: {:pkcs12, "missing.p12", password: "not-used"}
             )
  end
end
