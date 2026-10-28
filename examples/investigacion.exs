alias PaperForge.Declarative

template = Path.expand("investigacion.paperforge", __DIR__)
output = Path.expand("../output/pdf/investigacion.pdf", __DIR__)
signed_output = Path.expand("../output/pdf/investigacion_signed.pdf", __DIR__)
fixture_dir = Path.expand("../test/fixtures", __DIR__)

File.mkdir_p!(Path.dirname(output))
{:ok, document_template} = Declarative.load(template)

protected_template = Map.put(document_template, "signature", %{})
{:ok, report} = Declarative.write(protected_template, %{}, output)

IO.puts("Generated #{output}")
IO.puts("Template hash: #{report.template_hash}")
IO.puts("Demo open password: magg1999")

# Repository fixtures are demonstration credentials and are not shipped in Hex.
# Applications can provide their own PKCS#8 key and certificate paths.
key_path = System.get_env("PAPERFORGE_SIGNING_KEY") || Path.join(fixture_dir, "signing_key.pem")

cert_path =
  System.get_env("PAPERFORGE_SIGNING_CERT") || Path.join(fixture_dir, "signing_cert.pem")

if File.regular?(key_path) and File.regular?(cert_path) do
  signed_template =
    document_template
    |> Map.put("forms", [])
    |> Map.put("security", %{})

  {:ok, signed_report} =
    Declarative.write(signed_template, %{}, signed_output,
      signature: [certificate: {:pkcs8, key_path: key_path, cert_path: cert_path}]
    )

  IO.puts("Generated #{signed_output}")
  IO.puts("Signed template hash: #{signed_report.template_hash}")
else
  IO.puts("Signing skipped: set PAPERFORGE_SIGNING_KEY and PAPERFORGE_SIGNING_CERT to sign.")
end
