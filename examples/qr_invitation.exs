{:ok, template} = PaperForge.Declarative.load(Path.join(__DIR__, "qr_invitation.paperforge"))
# The application sends data; all presentation remains in the template.
data = %{
  qr_code: "b874a89e-8397-4fb1-9411-000000000001",
  guest_name: "María García",
  qr_size: 108
}

{:ok, document, _report} = PaperForge.Declarative.render(template, data)
path = Path.expand("../output/pdf/qr-invitation.pdf", __DIR__)
File.mkdir_p!(Path.dirname(path))
PaperForge.write!(document, path)
IO.puts(path)
