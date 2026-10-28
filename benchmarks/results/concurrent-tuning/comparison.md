# Concurrent rendering tuning

Local sequential runs: 300 PDFs per sample, three samples per scenario/concurrency, warmup before each sample. Values below are medians; peak memory is the maximum reported job sample. No HTTP, disk or upload work is timed. This compares the pre-tuning working tree to these changes, not released versions. Runs were not randomized; short measurements are sensitive to OS noise.

The conservative configuration keeps the 233-word default and initial collection. The tuned configuration requests 16,384 words and skips that initial collection. Larger heaps trade memory for allocation speed. Intermediate JSON files are exploratory measurements, retained for transparency.

| Scenario | Workers | Before PDF/s | Default PDF/s | Tuned PDF/s | Before peak bytes | Default peak bytes | Tuned peak bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| small | 1 | 10,030 | 10,278 | 14,202 | 47,312 | 124,481 | 162,158 |
| small | 4 | 21,215 | 29,470 | 33,674 | 47,312 | 124,481 | 162,158 |
| small | 10 | 32,985 | 37,841 | 41,288 | 47,312 | 124,481 | 162,158 |
| qr | 1 | 249 | 249 | 259 | 454,500 | 715,607 | 772,370 |
| qr | 4 | 921 | 810 | 960 | 460,081 | 715,607 | 772,370 |
| qr | 10 | 1,430 | 1,440 | 1,467 | 460,082 | 715,607 | 772,370 |
| visual | 1 | 349 | 354 | 381 | 437,160 | 437,021 | 390,604 |
| visual | 4 | 1,259 | 1,374 | 1,316 | 437,160 | 437,021 | 390,604 |
| visual | 10 | 2,016 | 2,040 | 2,163 | 437,160 | 437,021 | 390,604 |

All three reported runs completed with 0 failed jobs.

Use the default unless representative measurements justify tuning. Do not treat improvements in the small scenario as a universal gain or use these short samples to size a production SaaS. Memory figures are per-job sampled accounting, not whole-VM RSS.

Reproduce after compiling with MIX_ENV=prod; set TUNING_OUTPUT to a new JSON filename and optionally WORKER_HEAP=16384, then run mix run --no-compile benchmarks/concurrent_tuning.exs. Use the same scheduler count (10 here) and avoid simultaneous workloads.
