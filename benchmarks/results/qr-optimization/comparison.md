# QR invitation rendering comparison

Measured on the same host in prod, Elixir 1.20.2 / OTP 29 / 10 schedulers. Same benchmark source, 500 distinct UUID payloads per run, three repeats at each concurrency. Includes QR encoding, layout and serialization; excludes file/network I/O. Final run had no other agent commands running.

| Workers | Before PDF/s (median) | After PDF/s (median) | Change |
|---:|---:|---:|---:|
| 1 | 223.08 | 248.11 | +11.2% |
| 4 | 863.61 | 892.97 | +3.4% |
| 10 | 1311.71 | 1387.39 | +5.8% |

Median PDF size (100 payloads): 2813 → 2320 bytes.

Zero failures in all nine final runs (4,500 documents). The optimized renderer batches contiguous dark modules into rectangle subpaths and paints them once, plus a white quiet-zone background. Payload encoding remains Qiroex; no payload cache is used.

Limitations: short local benchmark, before and after were sequential rather than randomized paired runs. OS scheduling, temperature and other machine activity are not controlled. These are observed results for this small one-page QR workload, not a general throughput guarantee, a production capacity estimate or a comparison against release 1.4. The historical exhaustive campaign is unchanged.

Intermediate after.json used line-based paths and regressed; after-rectangles.json was exploratory and overlapped other verification commands. Use final.json for the final implementation; all raw results retained.
