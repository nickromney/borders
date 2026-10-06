# Optimized source sampling — 6 October 2026

Separate15-second pure-core child workloads were sampled for10seconds at1ms.
These are actual optimized `-O -g` source profiles, not idle windowserver or
camera/capture profiles. Both children checked their operation-result checksum;
selection order999 and mean luminance0.5 remain the goldens. The main loop and
sentinel/core functions appear in the samples, so work was not hoisted away.

| Rank | Workload | Observed source stack | Samples | Evidence |
| --- | --- | --- | ---: | --- |
| 1 | Focused selection | selectSyntheticWindow → WindowSelection.primary | 7556 of7583 main-thread samples | [raw selection sample](focused-selection.sample.txt) |
| 1 | Luminance | measureSyntheticLuminance → LuminanceMeasurement.mean | 7759 of7776 main-thread samples | [raw luminance sample](luminance-core.sample.txt) |

Selection's collapsed leaves include CGRect width/height access and candidate
comparisons; luminance's sampled source concentrates in its sample reduction.
This supports attribution to the intended pure workloads. It does not identify
real application lifecycle, window enumeration, overlays, actual capture,
CVPixelBuffer sampling, hardware, wakeup, I/O or allocation costs. No optimizer
change or causal speedup is proposed.

Host before/after observations show38.15%/39.0% idle and substantial background
load. These profiles have no controlled timing baseline; operation counts divided
by the profile duration must not be reported as benchmark throughput. Raw sample
counts are profiler observations, not operation counts or independent trials.
Physical footprint in sample output is distinct from peakRSS and allocation.

The fingerprint records the exact captured optimized binary and source hashes.
`main.swift.profile-source.txt` preserves that capture's harness source: a later
baseline-only checksum assertion changed from exact equality to tolerance1e-8,
matching existing floating-point golden tolerance. That baseline branch was not
executed by these profile processes; production core functions are unchanged.
