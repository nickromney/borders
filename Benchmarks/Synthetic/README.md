# Synthetic profiling preparation

Two separate, deterministic workloads call production pure-core functions:
1,000 candidate focused-window selection and mean luminance of 1,600 grey RGB
samples. Each records 20 batches of 1,000 operations and consumes its results.
The golden checks are window order 999 and normalized luminance 0.5. The harness
constructs no app runtime, hardware adapters, preferences, sessions, or sockets.

Build with optimized code and debug information, without stripping symbols:

```sh
mkdir -p .build
swiftc -O -g -module-cache-path .build/profile-module-cache Sources/BordersCore/*.swift Benchmarks/Synthetic/main.swift -o .build/synthetic-profile
.build/synthetic-profile --check  # safe golden-only proof under other build load
# Only after the baseline preconditions below hold:
.build/synthetic-profile > .build/synthetic-profile.jsonl
```

Before recording a baseline, fingerprint the host/toolchain/build/git SHA, stop
other heavy jobs, and confirm a stable power state. Run this on one host, report
p50/p95/max across the 20 batches, and check variance before attributing cost.
Sample the optimized binary separately if it runs long enough to attribute CPU.
Do not tune OS settings or ship optimization based on these timings.

These workloads prepare an offline baseline, not a profile of idle window
polling or camera acquisition. Actual `CGWindowListCopyWindowInfo`, timer/wakeup,
CVPixelBuffer sampling, capture, and overlay costs are excluded. Measure those
separately under an attended desktop/camera scenario; camera remains opt-in.
Keep geometry/settings and socket-timeout tests in the regression gate.

## Reusable collection

After other compiler/full-test gates finish, use the optimized binary above:

```sh
python3 Benchmarks/Synthetic/collect.py --output NEW_EVIDENCE_DIRECTORY
```

The collector requires macOS numeric `top` access. It preserves five preflight
CPU/load samples and refuses workload timing unless all observations have at
least 85% idle and their spread is at most ten percentage points. Every rejected
attempt remains evidence. No OS/power tuning or other-process control occurs.

Two seeded randomized conditions run serially: three discarded process warmups
then twenty measured processes per scenario. Each process discards three
internal batch warmups and measures twenty batches of 1,000 operations. All
23,000 operation results contribute to an asserted checksum; selection order999
and luminance0.5 remain the goldens. Boundary host CPU/load samples, whole-child
wall/CPU time and whole-process high-water RSS are distinct from inner batch
measurements. Ten or twenty process samples cannot establish extreme tail
latency. Report variance and background activity, not a causal speedup.

The separate profile mode extends exactly one pure workload for15seconds,
asserting its result checksum. `/usr/bin/sample` records ten seconds of only that
collector-owned child; sampler runs are excluded from the timing table. No
running Borders app, WindowServer, camera, CVPixelBuffer, capture session,
overlay, device adapter, preferences or permission state is read or changed.
`--allow-shared-host` is available only for explicitly qualified future
observations, never an isolated comparison or regression threshold.

The collector also checks each before/after workload observation against the preflight idle envelope. A failed before observation prevents the next workload; a failed after observation retains the row and rejects the collection without writing a successful summary. Boundary samples cannot prove uninterrupted isolation. Historical fingerprints and hash receipts describe their captured collector/source versions; they do not attest to the final edited collector.
