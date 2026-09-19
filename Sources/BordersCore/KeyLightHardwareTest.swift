import Foundation

/// The repeatable sequence used by the opt-in, camera-assisted hardware test.
public enum KeyLightHardwareTestStep: String, CaseIterable, Codable, Hashable, Sendable {
    case powerOff = "power-off"
    case zeroBrightness = "brightness-zero"
    case minimumOn = "minimum-on"
    case midpoint = "midpoint"
    case maximumOn = "maximum-on"

    public var title: String {
        switch self {
        case .powerOff: return "Power off"
        case .zeroBrightness: return "User 0%"
        case .minimumOn: return "Minimum on"
        case .midpoint: return "Midpoint"
        case .maximumOn: return "Maximum on"
        }
    }

    public var expectsLightOn: Bool {
        switch self {
        case .powerOff, .zeroBrightness: return false
        case .minimumOn, .midpoint, .maximumOn: return true
        }
    }
}

/// Timing and acceptance thresholds for one physical test run.
public struct KeyLightHardwareTestConfiguration: Codable, Equatable, Sendable {
    public let settleInterval: TimeInterval
    public let sampleCount: Int
    public let sampleInterval: TimeInterval
    public let tolerance: Double

    public init(settleInterval: TimeInterval = 1.0,
                sampleCount: Int = 5,
                sampleInterval: TimeInterval = 0.3,
                tolerance: Double = 0.05) {
        self.settleInterval = Self.clamp(settleInterval, lower: 0.3, upper: 30, fallback: 1.0)
        self.sampleCount = min(100, max(1, sampleCount))
        self.sampleInterval = Self.clamp(sampleInterval, lower: 0.1, upper: 5, fallback: 0.3)
        self.tolerance = Self.clamp(tolerance, lower: 0, upper: 1, fallback: 0.05)
    }

    private enum CodingKeys: String, CodingKey {
        case settleInterval
        case sampleCount
        case sampleInterval
        case tolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            settleInterval: try container.decodeIfPresent(TimeInterval.self, forKey: .settleInterval) ?? 1.0,
            sampleCount: try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 5,
            sampleInterval: try container.decodeIfPresent(TimeInterval.self, forKey: .sampleInterval) ?? 0.3,
            tolerance: try container.decodeIfPresent(Double.self, forKey: .tolerance) ?? 0.05
        )
    }

    private static func clamp(_ value: Double,
                              lower: Double,
                              upper: Double,
                              fallback: Double) -> Double {
        let finiteValue = value.isFinite ? value : fallback
        return min(upper, max(lower, finiteValue))
    }
}

/// The state returned by the light and the luminance measured after it settles.
public struct KeyLightHardwareObservation: Codable, Equatable, Sendable {
    public let step: KeyLightHardwareTestStep
    public let confirmedState: KeyLightState
    public let measuredLuminance: Double

    public init(step: KeyLightHardwareTestStep,
                confirmedState: KeyLightState,
                measuredLuminance: Double) {
        self.step = step
        self.confirmedState = confirmedState
        self.measuredLuminance = measuredLuminance
    }
}

/// Pure command generation for the hardware sequence.
public enum KeyLightHardwareTestPlan {
    public static let steps = KeyLightHardwareTestStep.allCases

    public static func command(for step: KeyLightHardwareTestStep,
                               basedOn base: KeyLightState) -> KeyLightState {
        switch step {
        case .powerOff:
            return base.changing(isOn: false)
        case .zeroBrightness:
            return base.changingForUserBrightness(0)
        case .minimumOn:
            return base.changing(isOn: true, brightness: KeyLightLimits.minimumVisibleBrightness)
        case .midpoint:
            return base.changing(isOn: true, brightness: 50)
        case .maximumOn:
            return base.changing(isOn: true, brightness: KeyLightLimits.brightness.upperBound)
        }
    }
}

/// Compares camera observations with the contract exposed by the UI.
public enum KeyLightHardwareTestEvaluator {
    public static func failures(in observations: [KeyLightHardwareObservation],
                                tolerance: Double = 0.05) -> [String] {
        let indexed = index(observations)
        let missing = missingSteps(in: indexed)
        guard missing.isEmpty else { return missing }

        let allowedTolerance = normalizedTolerance(tolerance)
        var failures = stateFailures(in: indexed)
        failures.append(contentsOf: measurementFailures(in: indexed))
        failures.append(contentsOf: orderingFailures(in: indexed, tolerance: allowedTolerance))
        return failures
    }

    private static func index(_ observations: [KeyLightHardwareObservation])
        -> [KeyLightHardwareTestStep: KeyLightHardwareObservation] {
        observations.reduce(into: [:]) { result, observation in
            result[observation.step] = observation
        }
    }

    private static func missingSteps(in observations: [KeyLightHardwareTestStep: KeyLightHardwareObservation]) -> [String] {
        KeyLightHardwareTestPlan.steps.compactMap { step in
            observations[step] == nil ? "Missing observation: \(step.rawValue)" : nil
        }
    }

    private static func stateFailures(in observations: [KeyLightHardwareTestStep: KeyLightHardwareObservation]) -> [String] {
        KeyLightHardwareTestPlan.steps.compactMap { step in
            guard let observation = observations[step],
                  observation.confirmedState.isOn != step.expectsLightOn else { return nil }
            return "Unexpected power state at \(step.rawValue)"
        }
    }

    private static func measurementFailures(in observations: [KeyLightHardwareTestStep: KeyLightHardwareObservation]) -> [String] {
        KeyLightHardwareTestPlan.steps.compactMap { step in
            guard let observation = observations[step], !observation.measuredLuminance.isFinite else { return nil }
            return "Non-finite luminance at \(step.rawValue)"
        }
    }

    private static func orderingFailures(in observations: [KeyLightHardwareTestStep: KeyLightHardwareObservation],
                                         tolerance: Double) -> [String] {
        guard let off = observations[.powerOff],
              let zero = observations[.zeroBrightness],
              let minimum = observations[.minimumOn],
              let midpoint = observations[.midpoint],
              let maximum = observations[.maximumOn] else { return [] }

        var failures: [String] = []
        if abs(zero.measuredLuminance - off.measuredLuminance) > tolerance {
            failures.append("User 0% does not match power off")
        }
        if minimum.measuredLuminance + tolerance < off.measuredLuminance {
            failures.append("Minimum on is darker than power off")
        }
        if midpoint.measuredLuminance + tolerance < minimum.measuredLuminance {
            failures.append("Midpoint is darker than minimum on")
        }
        if maximum.measuredLuminance + tolerance < midpoint.measuredLuminance {
            failures.append("Maximum on is darker than midpoint")
        }
        if maximum.measuredLuminance <= off.measuredLuminance + tolerance {
            failures.append("Maximum on is not brighter than power off")
        }
        return failures
    }

    private static func normalizedTolerance(_ tolerance: Double) -> Double {
        guard tolerance.isFinite else { return 0.05 }
        return min(1, max(0, tolerance))
    }
}
