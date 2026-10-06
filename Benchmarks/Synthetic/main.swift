import Foundation
import Darwin

// Profiling-only input. No BorderEngine, window enumeration, capture session,
// preferences, socket client, network, or hardware adapter is constructed.
@inline(never)
func selectSyntheticWindow(_ windows: [WindowCandidate]) -> Int {
    WindowSelection.primary(among: windows)?.order ?? -1
}

@inline(never)
func measureSyntheticLuminance(_ samples: [RGBSample]) -> Double {
    LuminanceMeasurement.mean(of: samples) ?? -1
}

let windows = (0..<1000).map {
    WindowCandidate(order: $0, frame: CGRect(x: 0, y: 0, width: 100 + $0, height: 100 + $0))
}
let samples = Array(repeating: RGBSample(red: 0.5, green: 0.5, blue: 0.5), count: 1600)
precondition(selectSyntheticWindow(windows) == 999)
precondition(abs(measureSyntheticLuminance(samples) - 0.5) < 1e-12)
if CommandLine.arguments.contains("--check") {
    print("Synthetic golden outputs passed; no timing baseline collected.")
    exit(0)
}
for scenario in ["focused-selection", "luminance-core"] {
    var runs: [Double] = []
    var checksum = 0.0
    for _ in 0..<20 {
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<1000 {
            checksum += scenario == "focused-selection"
                ? Double(selectSyntheticWindow(windows)) : measureSyntheticLuminance(samples)
        }
        runs.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    let output: [String: Any] = ["scenario": scenario, "iterations_per_run": 1000,
                               "runs_ms": runs, "checksum": checksum]
    print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
}
