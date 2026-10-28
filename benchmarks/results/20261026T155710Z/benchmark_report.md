# PaperForge Core benchmark report

COMPLETE

## Scope and reproducibility

Core PDF generation only. No Phoenix, databases, network, storage service or platform simulation. See `environment.md`, `commands.jsonl`, the Core patch/digest and archived runner sources. Measurements use `MIX_ENV=prod` and `--no-compile`; warmups precede every series. No Core changes or commits are made during the campaign.

## Reference documents

Latency and the main concurrent campaign use the same unchanged reference document: Small 25 rows/2 pages, Medium 500/18, Large 5000/179. The legacy concurrent mode remains available but omits two paragraphs; its Small output is 1 page. Minimal retains its original one-page indexed text. Consequently historical concurrent results are contextual, not an equivalent controlled comparison.

Each reference is parsed before timing. Every generated reference-profile PDF is checked against its deterministic reference SHA-256, envelope and page count. Only the reference PDFs are retained. Minimal outputs vary by index; their ordered aggregate digest should match across repetitions and concurrency levels.

## Individual latency

`single_render_ms` = layout + first serialization. Historical `total_ms` additionally includes a second warm serialization, retained for compatibility. Preparation is separately timed. Process peak memory is sampled and may miss brief peaks; GC counts in this runner are VM-wide, not per-process. CPU/RSS summaries encompass process launch and warmups, whereas Core timers exclude them.

| Profile | Pages | Bytes | Single PDF median ms | p95 ms | p99 ms | Historical total median ms |
|---|---:|---:|---:|---:|---:|---:|
| small | 2 | 4536 | 2.02 | 3.17 | 5.14 | 2.06 |
| medium | 18 | 62416 | 38.20 | 41.68 | 84.85 | 38.33 |
| large | 179 | 616481 | 825.98 | 921.48 | 1043.62 | 828.99 |

## Throughput and concurrency

The maximum is the best individual completed run. The recommended concurrency maximizes the median of repeated runs; it is workload- and machine-specific. Throughput includes bounded job scheduling, validation and lightweight JSONL instrumentation. Per-job `engine_us` separately times rendering, while job latency includes validation. No binary PDFs are retained in result collections.

| Profile | Max PDF/s | Best median workers | Median PDF/s | Max observed PDF/hour | Max observed PDF/24h | Peak RSS MiB | Peak BEAM MiB |
|---|---:|---:|---:|---:|---:|---:|---:|
| minimal | 44894.02 | 4 | 40427.58 | 161,618,484 | 3,878,843,604 | 147.3 | 72.0 |
| small | 2901.60 | 16 | 2691.87 | 10,445,773 | 250,698,560 | 165.1 | 114.4 |
| medium | 96.38 | 16 | 86.02 | 346,951 | 8,326,835 | 384.4 | 330.3 |
| large | 4.27 | 10 | 3.82 | 15,377 | 369,058 | 1421.9 | 1803.0 |

## Sustained throughput

| Profile | Workers | PDF/s | First third PDF/s | Last third PDF/s | Change | Failures |
|---|---:|---:|---:|---:|---:|---:|
| small | 16 | 1537.07 | 1584.19 | 1519.16 | -4.1% | 0 |
| medium | 16 | 69.12 | 71.43 | 69.25 | -3.1% | 0 |
| large | 10 | 3.10 | 3.14 | 3.06 | -2.6% | 0 |

## Scheduler scaling

`schedulers.csv` records actual schedulers inside each VM. Limiting BEAM schedulers does not pin processes to cores or emulate a VPS/vCPU allocation. Apple performance and efficiency cores are heterogeneous. CPU 100% means one logical CPU; values can exceed 100%. RSS is OS resident memory; BEAM totals include allocator/accounting differences and are not interchangeable.

| Schedulers | Workers | Median PDF/s | PDF/s per scheduler | Runs |
|---|---:|---:|---:|---:|
| s2 (2 effective) | 1 | 23.31 | 11.66 | 3 |
| s2 (2 effective) | 2 | 38.83 | 19.42 | 3 |
| s2 (2 effective) | 4 | 40.88 | 20.44 | 3 |
| s2 (2 effective) | 8 | 38.52 | 19.26 | 3 |
| s2 (2 effective) | 10 | 36.56 | 18.28 | 3 |
| s4 (4 effective) | 1 | 24.02 | 6.00 | 3 |
| s4 (4 effective) | 2 | 43.52 | 10.88 | 3 |
| s4 (4 effective) | 4 | 50.26 | 12.56 | 3 |
| s4 (4 effective) | 8 | 49.19 | 12.30 | 3 |
| s4 (4 effective) | 10 | 50.68 | 12.67 | 3 |
| s6 (6 effective) | 1 | 23.82 | 3.97 | 3 |
| s6 (6 effective) | 2 | 41.96 | 6.99 | 3 |
| s6 (6 effective) | 4 | 49.12 | 8.19 | 3 |
| s6 (6 effective) | 8 | 64.76 | 10.79 | 3 |
| s6 (6 effective) | 10 | 64.51 | 10.75 | 3 |
| s8 (8 effective) | 1 | 23.50 | 2.94 | 3 |
| s8 (8 effective) | 2 | 41.33 | 5.17 | 3 |
| s8 (8 effective) | 4 | 52.34 | 6.54 | 3 |
| s8 (8 effective) | 8 | 71.94 | 8.99 | 3 |
| s8 (8 effective) | 10 | 75.35 | 9.42 | 3 |
| s10 (10 effective) | 1 | 23.93 | 2.39 | 3 |
| s10 (10 effective) | 2 | 39.55 | 3.96 | 3 |
| s10 (10 effective) | 4 | 49.83 | 4.98 | 3 |
| s10 (10 effective) | 8 | 68.12 | 6.81 | 3 |
| s10 (10 effective) | 10 | 68.80 | 6.88 | 3 |
| sdefault (10 effective) | 1 | 23.72 | 2.37 | 3 |
| sdefault (10 effective) | 2 | 41.41 | 4.14 | 3 |
| sdefault (10 effective) | 4 | 49.81 | 4.98 | 3 |
| sdefault (10 effective) | 8 | 69.85 | 6.98 | 3 |
| sdefault (10 effective) | 10 | 75.16 | 7.52 | 3 |

## Comparison with 1.4.4

Supplied historical medians: Small 1.90 ms, Medium 39.13 ms, Large 824.77 ms. Historical Medium throughput: 24.52 / 45.11 / 89.93 / 122.80 PDF/s at 1 / 2 / 5 / 10 workers; Large: 2.12 / 4.99 at 2 / 10 workers. The old raw results, exact timing boundary and frozen source are not supplied. Current reference-profile concurrency has extra content relative to the old concurrent runner, and instrumentation differs. Do not attribute numerical differences to engine changes.

## Limits and interpretation

- Capacity/hour and /24h are arithmetic extrapolations from observed throughput, not measured daily production capacity or VPS predictions. Real service limits, contention, throttling and external work are excluded.
- No thermal sensor or power telemetry is assumed available. Raw `pmset -g therm` reports are retained. Absence of an OS warning cannot establish absence of thermal throttling. Ten-second cooldowns and recorded repeat order reduce, but do not eliminate, thermal/order effects.
- The host is not dedicated; editor and OS activity can affect timings. Memory guards stop a configuration above 8 GB RSS or below 10% system free-memory indicator, and skip starting below 15%. This indicator is not a precise measurement of allocatable RAM.
- OS CPU/RSS sampling is approximately 1 second; BEAM sampling is 200 ms. Peaks below those intervals may be missed. Sustained interval OS alignment has about 1.1 seconds of uncertainty; PDF interval counters are exact.
- Per-process peak memory from the existing concurrency wrapper can be zero for short jobs that finish before its first sample; zero does not mean zero allocation.
- Layout vs serialization timings help identify expensive stages; concurrency/GC trends suggest contention but cannot prove a specific bottleneck without a profiler. No optimizations are performed during measurement.
- Structural parsing and deterministic-byte checks do not replace independent visual verification or formal PDF conformance certification.

## Completion and failures

- concurrency: 69 completed configurations; 0 failed/skipped.
- schedulers: 90 completed configurations; 0 failed/skipped.
- sustained: 3 completed configurations; 0 failed/skipped.
