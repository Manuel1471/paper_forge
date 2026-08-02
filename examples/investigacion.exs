alias PaperForge.Declarative

template = Path.expand("investigacion.paperforge", __DIR__)
output = Path.expand("../output/pdf/investigacion.pdf", __DIR__)
signed_output = Path.expand("../output/pdf/investigacion_signed.pdf", __DIR__)
fixture_dir = Path.expand("../test/fixtures", __DIR__)

File.mkdir_p!(Path.dirname(output))
{:ok, document_template} = Declarative.load(template)

protected_template = Map.put(document_template, "signature", %{})
{:ok, report} = Declarative.write(protected_template, %{}, output)

signed_template =
  document_template
  |> Map.put("forms", [])
  |> Map.put("security", %{})

{:ok, signed_report} =
  Declarative.write(signed_template, %{}, signed_output,
    signature: [
      certificate:
        {:pkcs8,
         key_path: Path.join(fixture_dir, "signing_key.pem"),
         cert_path: Path.join(fixture_dir, "signing_cert.pem")}
    ]
  )

IO.puts("Generated #{output}")
IO.puts("Template hash: #{report.template_hash}")
IO.puts("Open password: magg1999")
IO.puts("Generated #{signed_output}")
IO.puts("Signed template hash: #{signed_report.template_hash}")
