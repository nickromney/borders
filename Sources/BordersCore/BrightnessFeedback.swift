import Foundation

/// A small, normalized RGB sample from a camera frame.
public struct RGBSample: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

/// Converts camera RGB samples into a repeatable, normalized luminance reading.
public enum LuminanceMeasurement {
    public static func mean(of samples: [RGBSample]) -> Double? {
        guard !samples.isEmpty else { return nil }

        let total = samples.reduce(0.0) { partial, sample in
            partial + (0.2126 * sample.red) + (0.7152 * sample.green) + (0.0722 * sample.blue)
        }
        return total / Double(samples.count)
    }

    /// Converts the Y plane of a video-range 8-bit YUV frame to 0...1.
    public static func normalizedVideoRangeLuma(_ value: Double) -> Double {
        normalizedLuma(value, black: 16, range: 219)
    }

    /// Converts the Y plane of a full-range 8-bit YUV frame to 0...1.
    public static func normalizedFullRangeLuma(_ value: Double) -> Double {
        normalizedLuma(value, black: 0, range: 255)
    }

    private static func normalizedLuma(_ value: Double, black: Double, range: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, (value - black) / range))
    }
}

/// Tuning knobs for the deliberately conservative camera feedback loop.
public struct BrightnessFeedbackConfiguration: Codable, Equatable, Sendable {
    public let targetLuminance: Double
    public let deadband: Double
    public let sampleCount: Int
    public let cooldown: TimeInterval
    public let maximumStep: Int
    public let sampleInterval: TimeInterval
    public let locksCameraExposure: Bool

    public init(targetLuminance: Double = 0.35,
                deadband: Double = 0.04,
                sampleCount: Int = 3,
                cooldown: TimeInterval = 1.5,
                maximumStep: Int = 4,
                sampleInterval: TimeInterval = 0.5,
                locksCameraExposure: Bool = true) {
        self.targetLuminance = min(1, max(0, targetLuminance.isFinite ? targetLuminance : 0.35))
        self.deadband = min(0.5, max(0.01, deadband.isFinite ? deadband : 0.04))
        self.sampleCount = max(1, sampleCount)
        self.cooldown = max(0, cooldown.isFinite ? cooldown : 1.5)
        self.maximumStep = max(1, maximumStep)
        self.sampleInterval = max(0.1, sampleInterval.isFinite ? sampleInterval : 0.5)
        self.locksCameraExposure = locksCameraExposure
    }

    private enum CodingKeys: String, CodingKey {
        case targetLuminance
        case deadband
        case sampleCount
        case cooldown
        case maximumStep
        case sampleInterval
        case locksCameraExposure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            targetLuminance: try container.decodeIfPresent(Double.self, forKey: .targetLuminance) ?? 0.35,
            deadband: try container.decodeIfPresent(Double.self, forKey: .deadband) ?? 0.04,
            sampleCount: try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 3,
            cooldown: try container.decodeIfPresent(TimeInterval.self, forKey: .cooldown) ?? 1.5,
            maximumStep: try container.decodeIfPresent(Int.self, forKey: .maximumStep) ?? 4,
            sampleInterval: try container.decodeIfPresent(TimeInterval.self, forKey: .sampleInterval) ?? 0.5,
            locksCameraExposure: try container.decodeIfPresent(Bool.self, forKey: .locksCameraExposure) ?? true
        )
    }
}

/// Pure control policy for camera-assisted brightness adjustment.
public struct BrightnessFeedbackPolicy: Sendable {
    private let configuration: BrightnessFeedbackConfiguration
    private var samples: [Double] = []
    private var lastAdjustmentAt: Date?

    public init(configuration: BrightnessFeedbackConfiguration = BrightnessFeedbackConfiguration()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        samples.removeAll()
        lastAdjustmentAt = nil
    }

    /// Returns a new brightness only when a stable, out-of-band reading is ready.
    public mutating func nextBrightness(for measuredLuminance: Double,
                                        currentBrightness: Int,
                                        at now: Date) -> Int? {
        guard measuredLuminance.isFinite else { return nil }

        samples.append(min(1, max(0, measuredLuminance)))
        guard let average = takeStableAverage(), cooldownHasElapsed(at: now),
              let step = step(for: average),
              let next = adjustedBrightness(currentBrightness, by: step) else { return nil }
        lastAdjustmentAt = now
        return next
    }

    private mutating func takeStableAverage() -> Double? {
        guard samples.count >= configuration.sampleCount else { return nil }
        let average = samples.reduce(0, +) / Double(samples.count)
        samples.removeAll()
        return average
    }

    private func cooldownHasElapsed(at now: Date) -> Bool {
        guard let lastAdjustmentAt else { return true }
        return now.timeIntervalSince(lastAdjustmentAt) >= configuration.cooldown
    }

    private func step(for average: Double) -> Int? {
        let error = configuration.targetLuminance - average
        guard abs(error) > configuration.deadband else { return nil }
        let requestedStep = Int((error * 100).rounded())
        let step = min(configuration.maximumStep, max(-configuration.maximumStep, requestedStep))
        return step == 0 ? nil : step
    }

    private func adjustedBrightness(_ brightness: Int, by step: Int) -> Int? {
        let current = min(KeyLightLimits.brightness.upperBound,
                          max(KeyLightLimits.minimumVisibleBrightness, brightness))
        let next = min(KeyLightLimits.brightness.upperBound,
                       max(KeyLightLimits.minimumVisibleBrightness, current + step))
        return next == current ? nil : next
    }
}

/// Stable camera identity and selection rules shared by UI adapters.
public struct BrightnessCameraCandidate: Equatable, Sendable {
    public let id: String
    public let name: String
    public let isExternal: Bool

    public init(id: String, name: String, isExternal: Bool) {
        self.id = id
        self.name = name
        self.isExternal = isExternal
    }
}

public enum BrightnessCameraSelectionPolicy {
    public static func sortedByPreference(_ devices: [BrightnessCameraCandidate]) -> [BrightnessCameraCandidate] {
        devices.sorted { lhs, rhs in
            let lhsScore = score(for: lhs)
            let rhsScore = score(for: rhs)
            // The inequality guard makes `>` and `>=` equivalent here; retaining
            // strict ordering is important to the comparator contract.
            if lhsScore != rhsScore { return lhsScore > rhsScore } // mutation:skip
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func score(for device: BrightnessCameraCandidate) -> Int {
        let name = device.name.lowercased()
        if isDocCamName(name) {
            return 300
        }
        return device.isExternal ? externalScore(for: name) : 0
    }

    private static func isDocCamName(_ name: String) -> Bool {
        ["gawervan", "kb-1300", "usb camera"].contains { name.contains($0) }
    }

    private static func externalScore(for name: String) -> Int {
        name.contains("logitech") ? 100 : 200
    }
}

/// A latest-value buffer for controls that produce many intermediate writes.
public struct KeyLightWriteCoalescer: Equatable, Sendable {
    private var pendingStates: [String: KeyLightState] = [:]

    public init() {}

    public var isEmpty: Bool { pendingStates.isEmpty }

    public mutating func replace(_ state: KeyLightState, for deviceID: String) {
        pendingStates[deviceID] = state
    }

    public mutating func takeLatest(for deviceID: String) -> KeyLightState? {
        pendingStates.removeValue(forKey: deviceID)
    }

    public mutating func remove(for deviceID: String) {
        pendingStates.removeValue(forKey: deviceID)
    }

    public mutating func removeAll() {
        pendingStates.removeAll()
    }
}

public enum KeyLightTiming {
    /// Delay after the last slider value before sending it to the light.
    public static let sliderWriteDebounce: TimeInterval = 0.3
}
