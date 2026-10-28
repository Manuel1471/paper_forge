# Verified benchmark environment

```json
{
  "utc": "20261026T155710Z",
  "commit": "9d4a2b8f5612d42c4319f39669d68b8a3b0ec120",
  "core_tree_sha256": "aaaf1e681cbb26a276708ea4d1be7d72124ed9527afbfa721492fab611192a52",
  "git_status": "M DECLARATIVE.md\n M RELEASE_REVIEW.md\n M benchmarks/concurrent_renders.exs\n M benchmarks/render_profiles.exs\n M lib/paper_forge/authoring/declarative.ex\n M lib/paper_forge/authoring/declarative/cache.ex\n M lib/paper_forge/authoring/declarative/validator.ex\n M lib/paper_forge/security/protection.ex\n M priv/paperforge.schema.json\n M test/paper_forge/protection_test.exs\n?? benchmarks/core_campaign.py\n?? benchmarks/support/\n?? examples/design_protection_review.paperforge\n?? test/paper_forge/declarative_cache_test.exs",
  "hardware": "machdep.cpu.brand_string: Apple M4\nhw.memsize: 17179869184\nhw.physicalcpu: 10\nhw.logicalcpu: 10\nhw.perflevel0.physicalcpu: 4\nhw.perflevel1.physicalcpu: 6",
  "os": "ProductName:\t\tmacOS\nProductVersion:\t\t26.5.2\nBuildVersion:\t\t25F84",
  "architecture": "arm64",
  "elixir": "Erlang/OTP 29 [erts-17.0.3] [source] [64-bit] [smp:10:10] [ds:10:10:10] [async-threads:1] [jit] [dtrace]\n\nElixir 1.20.2 (compiled with Erlang/OTP 29)",
  "mix": "Erlang/OTP 29 [erts-17.0.3] [source] [64-bit] [smp:10:10] [ds:10:10:10] [async-threads:1] [jit] [dtrace]\n\nMix 1.20.2 (compiled with Erlang/OTP 29)",
  "vm": "%{version: \"1.5.0\", schedulers: 10, available: 10, online: 10, mix_env: :prod}",
  "environment": {
    "MIX_ENV": "prod",
    "ERL_FLAGS": null,
    "ELIXIR_ERL_OPTIONS": null,
    "MIX_TARGET": null,
    "LANG": "C.UTF-8"
  },
  "thermal_initial": "Note: No thermal warning level has been recorded\nNote: No performance warning level has been recorded\nNote: No CPU power status has been recorded",
  "memory_free_percent_initial": 50
}
```

The working tree includes the reviewed 1.2/1.3 fixes. The commit alone does not identify it; use the archived patch and Core tree digest. No engine edits are allowed after this snapshot.

Power check during the campaign: AC power connected, battery 99% (macOS pmset).
