# PaperForge Production Scaling

This guide treats PDF generation as application infrastructure rather than an
unbounded function call.

## Recommended architecture

Separate document generation into durable stages:

1. Load and validate application data.
2. Build an immutable PaperForge document.
3. Paginate and render the document.
4. Write the PDF incrementally to local temporary storage.
5. Upload the completed artifact to durable object storage.
6. Persist status, metrics, checksum, and storage location.

Pass identifiers between stages instead of large binaries. This keeps queue
payloads small and allows any stage to be retried on another node.

## Phoenix supervision

Add a bounded task supervisor:

```elixir
children = [
  {Task.Supervisor, name: MyApp.PDFSupervisor}
]
```

Start with half the available schedulers for large reports:

```elixir
max_concurrency = max(div(System.schedulers_online(), 2), 1)
```

Use `PaperForge.Concurrent.stream/4` for in-memory batches. Configure
`max_memory_bytes`, `max_reductions`, `timeout`, and `max_attempts` according to
the representative workload benchmark.

## Oban integration

Oban remains optional and is not required by PaperForge. A worker can call the
public APIs directly:

```elixir
defmodule MyApp.Workers.RenderPDF do
  use Oban.Worker,
    queue: :pdf_render,
    max_attempts: 5,
    unique: [period: 300, fields: [:args]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => id}}) do
    path = MyApp.Documents.temporary_pdf_path(id)

    try do
      document = MyApp.Documents.build_pdf(id)

      with :ok <- PaperForge.write(document, path),
           {:ok, location} <- MyApp.Storage.upload(path, "#{id}.pdf") do
        MyApp.Documents.mark_ready(id, location)
        :ok
      end
    after
      File.rm(path)
    end
  end
end
```

Use separate Oban queues for data preparation, PDF rendering, and uploads when
those stages have different CPU, memory, or I/O characteristics. Configure
queue concurrency per node instead of starting an unbounded task inside every
Oban job.

## Distributed nodes

- Store job state and artifact locations in shared durable storage.
- Send document IDs through the queue, not `%PaperForge.Document{}` structs or
  PDF binaries.
- Make render jobs idempotent using a document version or content hash.
- Use deterministic destination keys so retries replace the same artifact.
- Allow any compatible node to claim a job.
- Drain rendering queues before deployments that change the PaperForge
  version or document template contract.
- Record the PaperForge version and template version with every generated
  artifact.

## Resource budgets and recovery

`PaperForge.Concurrent` can terminate a single render when it exceeds:

- `timeout`
- `max_memory_bytes`
- `max_reductions`

It can retry selected statuses using `max_attempts`, `retry_delay`, and
`retry_on`. Durable queues should remain the source of truth for retries across
node crashes. In-process retries are intended for short transient failures.

Treat timeouts and resource-limit failures differently from invalid document
input. Invalid input should normally fail permanently; transient storage or
service failures may be retried with exponential backoff at the queue layer.

## Very large documents

- Prefer `PaperForge.write/2` or `write!/2`. They write objects incrementally to
  a temporary file and atomically rename the completed PDF.
- Avoid retaining the returned binaries from many completed jobs. Upload or
  consume each file as the backpressured stream produces it.
- Split independently consumable reports into volumes when practical.
- Keep images deduplicated and sized near their intended output resolution.
- Benchmark the real fonts, images, tables, and page templates used in
  production.
- Set queue limits from p95 memory and latency, not from minimal-document
  throughput.

Incremental file output reduces the final PDF-binary duplication. Layout still
retains document and placement structures until rendering completes, so it is
not a constant-memory page streaming engine.

## Deployment sizing

Measure at least:

- document latency median and p95;
- batch throughput by concurrency level;
- per-job peak memory median and p95;
- total BEAM peak memory;
- reductions and garbage collections;
- timeout, resource-limit, retry, and permanent-failure counts;
- queue wait time separately from render time.

Reserve memory for the VM, application traffic, queue processes, and storage
clients. A conservative initial worker limit is:

```text
min(
  available schedulers / 2,
  memory available for PDF jobs / measured p95 job memory
)
```

On the reference machine, 179-page reports measured about 102 MB p95 per job.
One worker peaked near 308 MB total BEAM memory, five near 1.10 GB, and ten near
1.86 GB. Memory, rather than scheduler count, is the practical limit for that
workload.

Re-run `benchmarks/render_profiles.exs` and
`benchmarks/concurrent_renders.exs` on production-class hardware whenever
fonts, templates, image policies, Elixir, OTP, or PaperForge versions change.

## Observability

Attach production metrics to the events exposed by
`PaperForge.Telemetry.events/0`. Alert on:

- render exception and returned-error rates;
- timeout and resource-limit statuses;
- retry attempts greater than one;
- p95 render and queue latency;
- per-job and total BEAM memory;
- sustained queue depth;
- throughput falling below the representative workload baseline.

`Concurrent.run/3` emits `[:paperforge, :batch, :complete]`. A lazily consumed
`Concurrent.stream/4` emits per-attempt job events but intentionally does not
claim completion when a consumer stops early.
