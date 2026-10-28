# Core-only performance campaign

Run from the repository root after reviewing and freezing Core changes:

```sh
MIX_ENV=prod mix compile
python3 benchmarks/core_campaign.py
python3 benchmarks/summarize_campaign.py benchmarks/results/<timestamp>
```

This is a long, sequential campaign (hours, depending on the host). It creates
an exclusive timestamped directory, runs 100 measured latency samples after
10 warmups, all requested concurrency configurations three times, all scheduler
configurations three times, and 10/15/5 minute sustained Small/Medium/Large runs.
No results directories are overwritten. No commits or engine edits are made.

The host resource monitor currently targets macOS (`sysctl`, `ps`,
`memory_pressure`, `pmset`). It stops a configuration above 8 GB RSS or below
10% free-memory indicator and skips new configurations below 15%. This is not a
portable VPS harness. The original Elixir runners remain usable separately.

`REFERENCE_PROFILE=true` selects the exact latency profile in the concurrent
runner, including its heading and two paragraphs. Without it, the original
concurrent documents remain unchanged. `WORKLOAD=small` is now supported.
`RESULT_JSONL=/absolute/path` enables raw records; `DURATION_SECONDS=600`
selects a bounded time-based stream. Results are validated then discarded.

The legacy `total_ms` latency includes layout and two serializations;
`single_render_ms` excludes the second serialization. Both are reported.
Per-document concurrent timing includes validation; raw `engine_us` isolates
rendering. Throughput includes scheduling and measurement overhead. The
sustained runner retains only the most recent per-job duration/memory value;
its summary latency quantiles are not a sustained latency distribution.
Use its interval throughput, memory, CPU and GC records instead.

A completed campaign creates `complete.json`. Until that file exists,
`benchmark_report.md` is provisional. Re-run the summarizer after completion.
OS interval alignment has about 1.1 seconds of uncertainty; detailed process
and VM samples are preserved in `raw/`. Sampled peaks can miss shorter spikes.
Reference PDF bytes, pages and hashes are verified separately from timing.
