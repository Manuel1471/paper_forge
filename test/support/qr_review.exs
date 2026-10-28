# Independent scan fixture: mix run test/support/qr_review.exs
# Rasterize each page with pdftoppm, then run verify_qr.swift on the PNGs.
payloads = [
  "b874a89e-8397-4fb1-9411-000000000001",
  "https://example.com/invite/abc?guest=123",
  "Invitación: María, año 2026 · € · 東京"
]

root = Path.join(System.tmp_dir!(), "paperforge-qr-review")
File.mkdir_p!(root)

manifest =
  for {payload, index} <- Enum.with_index(payloads),
      origin <- [:top_left, :bottom_left],
      size <- [72, 144] do
    path = Path.join(root, "qr-#{index}-#{origin}-#{size}.pdf")

    page =
      PaperForge.Page.new(size: {240, 240}, origin: origin)
      |> PaperForge.Page.qr_code(payload, size: size, x: 40, y: 40, level: :h, quiet_zone: 6)

    PaperForge.new() |> PaperForge.add_page(page) |> PaperForge.write!(path)
    %{pdf: path, payload: payload}
  end

File.write!(Path.join(root, "manifest.json"), Jason.encode!(manifest, pretty: true))
IO.puts(root)
