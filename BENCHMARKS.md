# PaperForge Benchmark Suite

PaperForge benchmarks are reproducible workload definitions, not promises for
every machine. Run them with the same Elixir, OTP, scheduler count, hardware,
and `MIX_ENV=prod` when comparing revisions.

## Official workloads

| ID | Workload | Runner | Purpose |
| --- | --- | --- | --- |
| PF-BENCH-001 | Small report, 25 rows | `render_profiles.exs` | Single-document latency floor |
| PF-BENCH-002 | Medium report, 500 rows | `render_profiles.exs` | Typical multi-page reporting workload |
| PF-BENCH-003 | Large report, 5,000 rows | `render_profiles.exs` | Pagination, table, allocation, and GC pressure |
| PF-BENCH-004 | Concurrent minimal, medium, or large documents | `concurrent_renders.exs` | Throughput and bounded-concurrency behavior |

## Run latency profiles

```bash
MIX_ENV=prod SAMPLES=30 WARMUPS=3 mix run benchmarks/render_profiles.exs
```

Set `PROFILE=small`, `PROFILE=medium`, or `PROFILE=large` to isolate a single
document size. `SAMPLES` must be positive; `WARMUPS` may be zero. The runner reports median, p95, minimum, maximum, pages, bytes,
process-local peak sampling, reductions, garbage collections, reclaimed words,
and cache statistics.

## Run concurrent profiles

```bash
MIX_ENV=prod WORKLOAD=medium JOBS=100 CONCURRENCY=1,2,5,10 \
  mix run benchmarks/concurrent_renders.exs
```

Use `WORKLOAD=minimal`, `medium`, or `large`. The runner reports total elapsed
time, renders per second, job median and p95 latency, job-memory sampling,
BEAM-wide memory sampling, reductions, garbage collections, and failures.

## Comparison rules

- Warm up before collecting samples.
- Prefer medians and p95 over a single average.
- Record runtime versions and scheduler count with each result.
- Treat VM-wide memory as a workload-level signal; use process-local sampling
  when attributing memory to an individual render.
- Require byte-identical output for deterministic benchmark inputs.

## Reference results for 1.4.4

The following runs make the performance discussion concrete without pretending
that one laptop defines every deployment. They were collected on Apple Silicon
(`Mac16,12`) with `MIX_ENV=prod`, Elixir `1.20.2`, OTP `29`, and `10`
schedulers. Every latency profile used **3 warmups and 30 measured samples**.

| Profile | Content | Pages | Output | Total median | Total p95 | Layout median | Cold serialization median | Peak process memory median |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Small | 25 table rows | 2 | 4.5 KB | 1.90 ms | 2.06 ms | 1.68 ms | 0.19 ms | 1.12 MB |
| Medium | 500 table rows | 18 | 62.3 KB | 39.13 ms | 39.87 ms | 34.55 ms | 3.44 ms | 9.59 MB |
| Large | 5,000 table rows | 179 | 616 KB | 824.77 ms | 832.83 ms | 773.58 ms | 35.54 ms | 97.08 MB |

The p95 numbers show low variation on this host: `2.06 ms`, `39.87 ms`, and
`832.83 ms` respectively. These are same-revision reference measurements, not
a claimed speedup over another PaperForge version or a guarantee for every
machine.

What these results mean in plain language:

- Small documents finish in roughly two milliseconds after the runtime is warm.
- A 500-row report completed in about 39 milliseconds in this reference run.
- The 5,000-row workload paginated a 179-page report in about 825 milliseconds
  while keeping the output near 616 KB. It is the profile to use when
  evaluating large-table changes.
- Cache counters are included in every profile so a slowdown can be traced to
  text measurement, compression, or font-subset work instead of guessed at.

## Reference concurrency results for 1.4.4

Concurrency answers a different question: how many independent documents can a
BEAM application render under bounded load? These runs used the same runtime
and host as the latency table. Each row is one scaling run rather than a
30-sample latency distribution.

### Minimal one-page documents, 1,000 jobs

| Workers | Elapsed | Throughput | Job median | Job p95 | Failures |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 47.51 ms | 21,047.31 PDFs/s | 0.03 ms | 0.03 ms | 0 |
| 2 | 19.27 ms | 51,886.06 PDFs/s | 0.03 ms | 0.03 ms | 0 |
| 5 | 18.41 ms | 54,321.26 PDFs/s | 0.03 ms | 0.04 ms | 0 |
| 10 | 18.32 ms | 54,570.26 PDFs/s | 0.03 ms | 0.04 ms | 0 |

This is an infrastructure micro-benchmark for the bounded worker path, not a
claim that a complex invoice renders at 54,000 PDFs per second.

### Medium reports, 500 rows and 18 pages, 100 jobs

| Workers | Elapsed | Throughput | Job median | Job p95 | Peak BEAM memory | Failures |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 4.08 s | 24.52 PDFs/s | 40.38 ms | 41.41 ms | 95.14 MB | 0 |
| 2 | 2.22 s | 45.11 PDFs/s | 44.19 ms | 45.31 ms | 119.21 MB | 0 |
| 5 | 1.11 s | 89.93 PDFs/s | 55.10 ms | 59.10 ms | 183.63 MB | 0 |
| 10 | 814.30 ms | 122.80 PDFs/s | 79.78 ms | 88.69 ms | 247.13 MB | 0 |

### Large reports, 5,000 rows and 179 pages, 20 jobs

| Workers | Elapsed | Throughput | Job median | Job p95 | Peak BEAM memory | Failures |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 16.85 s | 1.19 PDFs/s | 835.63 ms | 848.21 ms | 305.94 MB | 0 |
| 2 | 9.44 s | 2.12 PDFs/s | 942.10 ms | 952.13 ms | 503.57 MB | 0 |
| 5 | 5.17 s | 3.87 PDFs/s | 1.27 s | 1.33 s | 1.04 GB | 0 |
| 10 | 4.01 s | 4.99 PDFs/s | 1.98 s | 2.04 s | 1.84 GB | 0 |

For the large workload, `2` workers are the practical memory-throughput
starting point on this reference machine. `5` workers can be appropriate only
when the deployment has at least about 1 GB of BEAM memory available for this
workload plus the application itself. Ten workers maximize throughput here but
also materially increase per-job latency and memory pressure.

## Release quality checks

Before the 1.4.4 reference measurements, the repository passed:

| Check | Result |
| --- | --- |
| `mix format --check-formatted` | Passed |
| `mix compile --warnings-as-errors` | Passed |
| `mix test` | 280 tests passed, including 1 property test |
| `mix hex.build` | Passed |

The test suite covers deterministic output, validation and diagnostics,
declarative templates, fonts, images, PDF interoperability, security, and
performance-cache regression cases. It verifies correctness; benchmark runners
measure speed and memory under explicit workloads.

## Planned workload expansion

Image-heavy, embedded-font, and AES-256 benchmark profiles will be added only
with dedicated reproducible runners and documented resource fixtures.
