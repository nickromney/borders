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
