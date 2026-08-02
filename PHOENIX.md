# PaperForge With Phoenix

This guide shows how to generate and deliver PaperForge documents from a
Phoenix application. PaperForge runs in the BEAM and requires no browser,
external rendering service, native executable, or installation-time
compilation.

## 1. Install PaperForge

Add PaperForge to `mix.exs`:

```elixir
defp deps do
  [
    {:phoenix, "~> 1.8"},
    {:paper_forge, "~> 1.4"}
  ]
end
```

Fetch and compile dependencies:

```bash
mix deps.get
mix compile
```

No PaperForge-specific child is required in the supervision tree for ordinary
synchronous generation.

## 2. Keep Document Construction Outside The Controller

Put document design in a context or dedicated module. Controllers should load
authorized data, call the builder, and deliver the result.

```elixir
defmodule MyApp.Documents.Invoice do
  alias PaperForge.Flow

  def build(invoice) do
    {document, _report} =
      PaperForge.new(compress: true)
      |> PaperForge.metadata(
        title: "Invoice #{invoice.number}",
        author: "My Company"
      )
      |> PaperForge.page_template(
        :invoice,
        size: :a4,
        margins: [top: 54, right: 48, bottom: 60, left: 48],
        footer: "Invoice #{invoice.number}  /  Page {page} of {total}"
      )
      |> PaperForge.layout(
        fn flow ->
          flow
          |> Flow.heading("Invoice #{invoice.number}", level: 1)
          |> Flow.paragraph("Customer: #{invoice.customer_name}")
          |> Flow.table(
            ["Description", "Quantity", "Total"],
            Enum.map(invoice.lines, fn line ->
              [line.description, to_string(line.quantity), line.formatted_total]
            end),
            repeat_header: true
          )
          |> Flow.paragraph("Amount due: #{invoice.formatted_total}")
        end,
        template: :invoice
      )

    document
  end
end
```

This separation makes authorization, rendering, and document layout easier to
test independently.

## 3. Download A PDF From A Controller

Add a route:

```elixir
get "/invoices/:id.pdf", InvoiceController, :download
```

Generate the document only after loading it through the application's normal
authorization boundary:

```elixir
def download(conn, %{"id" => id}) do
  invoice = MyApp.Billing.get_authorized_invoice!(conn.assigns.current_user, id)
  document = MyApp.Documents.Invoice.build(invoice)
  pdf = PaperForge.to_binary(document)

  conn
  |> put_resp_content_type("application/pdf")
  |> put_resp_header(
    "content-disposition",
    ~s(attachment; filename="invoice-#{invoice.number}.pdf")
  )
  |> put_resp_header("cache-control", "private, no-store")
  |> send_resp(:ok, pdf)
end
```

Use `inline` instead of `attachment` when the browser should open its PDF
viewer. Sanitize or generate filenames rather than placing arbitrary user input
inside `content-disposition`.

## 4. Render A `.paperforge` Template

Store application-owned templates under a dedicated directory such as
`priv/paperforge`. Resolve that path through the OTP application so releases do
not depend on the current working directory:

```elixir
defmodule MyApp.Documents.Report do
  def build(data) do
    root = Application.app_dir(:my_app, "priv/paperforge")
    path = Path.join(root, "annual_report.paperforge")

    with {:ok, template} <- PaperForge.Declarative.load(path, root: root),
         {:ok, document, report} <-
           PaperForge.Declarative.render(template, data, root: root, cache: true) do
      {:ok, document, report}
    end
  end
end
```

Keep templates under application control. Treat request parameters as template
data, validate them through declared variables, and retain the default loop,
block, table, and file-size limits.

For final write-time encryption or signing, obtain secrets from the deployment
secret manager rather than the template or request:

```elixir
PaperForge.Declarative.write(template, data, destination,
  root: root,
  security: [
    user_password: recipient_password,
    owner_password: System.fetch_env!("PDF_OWNER_PASSWORD")
  ],
  signature: [
    certificate:
      {:pkcs8,
       key_path: System.fetch_env!("PDF_SIGNING_KEY"),
       cert_path: System.fetch_env!("PDF_SIGNING_CERT"),
       password: System.get_env("PDF_SIGNING_KEY_PASSWORD")}
  ]
)
```

The default PKCS#8 signer uses Elixir/OTP only. OpenSSL is used only if the
application explicitly selects the optional PKCS#12/PFX certificate source.

## 5. Trigger Downloads From LiveView

Keep the PDF response in a controller route. A LiveView event can navigate to
that authenticated endpoint instead of placing a large PDF binary in the
LiveView socket:

```elixir
def handle_event("download_invoice", %{"id" => id}, socket) do
  {:noreply, push_navigate(socket, to: ~p"/invoices/#{id}.pdf")}
end
```

For generation that takes longer than a normal request, enqueue a job and show
its status in LiveView. When it completes, expose an authenticated download URL
or a short-lived object-storage URL.

## 6. Large Documents And Concurrent Traffic

Direct `PaperForge.to_binary/1` responses are appropriate when measured render
latency and memory fit the application's HTTP request budget. For large reports
or burst traffic:

1. Generate outside the request process.
2. Bound concurrent jobs.
3. Write to a unique temporary path.
4. Upload the completed file to durable storage.
5. Persist the status and storage key.
6. Delete temporary files in an `after` block.

Add a supervisor when using PaperForge's in-process concurrent APIs:

```elixir
children = [
  {Task.Supervisor, name: MyApp.PDFSupervisor}
]
```

Set concurrency from measured p95 render memory, not only the number of CPU
schedulers. `PaperForge.Concurrent` supports timeouts, cancellation, retries,
memory limits, reductions limits, isolated job errors, and backpressure.

## 7. Optional Oban Worker

PaperForge does not require Oban. It is useful when generation must survive
node restarts, be retried durably, or execute outside an HTTP request:

```elixir
defmodule MyApp.Workers.GenerateInvoicePDF do
  use Oban.Worker, queue: :pdf, max_attempts: 4

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"invoice_id" => id}}) do
    invoice = MyApp.Billing.get_invoice!(id)
    document = MyApp.Documents.Invoice.build(invoice)
    path = Path.join(System.tmp_dir!(), "invoice-#{id}-#{Ecto.UUID.generate()}.pdf")

    try do
      with :ok <- PaperForge.write(document, path),
           {:ok, storage_key} <- MyApp.Storage.put_file(path, "invoices/#{id}.pdf") do
        MyApp.Billing.mark_pdf_ready(id, storage_key)
        :ok
      end
    after
      File.rm(path)
    end
  end
end
```

Pass stable identifiers through job arguments, not PDF binaries or
`%PaperForge.Document{}` values. Make jobs idempotent so a retry replaces or
reuses the intended artifact.

## 8. Error Handling

Validate documents before final delivery when input or templates may vary:

```elixir
with {:ok, document, _report} <- MyApp.Documents.Report.build(data),
     {:ok, _validation} <- PaperForge.validate(document) do
  {:ok, PaperForge.to_binary(document)}
else
  {:error, issues} -> {:error, {:invalid_document, issues}}
end
```

Map invalid business data to a controlled application error. Log structured
issue codes and paths, but do not log document passwords, signing keys,
certificate passwords, or private customer content.

## 9. Telemetry

Attach handlers during application startup for the events returned by
`PaperForge.Telemetry.events/0`. Record render duration, output bytes, pages,
memory, reductions, garbage collections, attempt, and status. Keep queue wait
time separate from PaperForge render time so capacity problems are visible.

Recommended production views include:

- render latency median and p95 by document type;
- peak memory p95 by document type;
- successful and failed renders;
- timeout and resource-limit counts;
- queue wait time and queue depth;
- output bytes and pages;
- retry attempts.

## 10. Test The Phoenix Integration

A controller test should verify status, headers, and the PDF signature:

```elixir
test "downloads an invoice PDF", %{conn: conn, invoice: invoice} do
  conn = get(conn, ~p"/invoices/#{invoice.id}.pdf")

  assert response_content_type(conn, :pdf) == "application/pdf"
  assert get_resp_header(conn, "content-disposition") =~ "attachment"
  assert <<"%PDF-", _::binary>> = response(conn, 200)
end
```

Test the builder separately for expected text, pages, navigation, validation,
and security structures. Keep a small number of rendered fixture PDFs for
visual regression review, and benchmark representative small, medium, and
large documents before selecting queue concurrency.

## Production Checklist

- Authorize access before loading document data or returning a PDF.
- Keep private PDFs out of public static directories.
- Use `private, no-store` or an application-appropriate cache policy.
- Keep credentials at the final output boundary.
- Use unique temporary files and always clean them up.
- Bound concurrency and configure timeouts and memory limits.
- Store durable artifacts outside the application node filesystem.
- Attach Telemetry and alert on failures, p95 latency, and p95 memory.
- Validate real templates and data in CI with `mix paper_forge.validate`.
- Run load tests with the same fonts, images, tables, and page counts used in
  production.

See [`PRODUCTION.md`](PRODUCTION.md) for distributed execution, deployment
sizing, throughput measurements, and failure-recovery guidance.

## Future Visual Authoring

A separate visual editor is planned for people who want to arrange documents
more quickly without working directly in Elixir or JSON. It is expected to read
and write ordinary `.paperforge` files, so it will be optional and will not
replace the open library or lock generated templates to the editor.

The current product direction is an affordable annual license associated with
supported editor versions rather than per-document charges. This note records
the intended direction only; availability, pricing, and support terms will be
published when the visual product is ready.
