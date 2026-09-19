import Foundation
import XCTest
@testable import BordersCore

final class KeyLightHardwareTestTests: XCTestCase {
    func testUserZeroCommandIsPowerOff() throws {
        let base = KeyLightState(isOn: true, brightness: 60, temperature: 4_200)
        let zero = KeyLightHardwareTestPlan.command(for: .zeroBrightness, basedOn: base)

        XCTAssertFalse(zero.isOn)
        XCTAssertEqual(zero.brightness, 0)
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: zero.apiPayloadData()) as? [String: Any]
        )
        let light = try XCTUnwrap((payload["lights"] as? [[String: Any]])?.first)
        XCTAssertEqual(payload["numberOfLights"] as? Int, 1)
        XCTAssertEqual(light["on"] as? Int, 0)
        XCTAssertEqual(light["brightness"] as? Int, 0)
        XCTAssertEqual(light["temperature"] as? Int, 238)
    }

    func testPlanCoversTheExpectedCommands() {
        let base = KeyLightState(isOn: true, brightness: 60, temperature: 4_200)

        XCTAssertEqual(KeyLightHardwareTestPlan.steps, KeyLightHardwareTestStep.allCases)
        XCTAssertFalse(KeyLightHardwareTestPlan.command(for: .powerOff, basedOn: base).isOn)
        let minimum = KeyLightHardwareTestPlan.command(for: .minimumOn, basedOn: base)
        XCTAssertTrue(minimum.isOn)
        XCTAssertEqual(minimum.brightness, 15)
        let midpoint = KeyLightHardwareTestPlan.command(for: .midpoint, basedOn: base)
        XCTAssertTrue(midpoint.isOn)
        XCTAssertEqual(midpoint.brightness, 50)
        let maximum = KeyLightHardwareTestPlan.command(for: .maximumOn, basedOn: base)
        XCTAssertTrue(maximum.isOn)
        XCTAssertEqual(maximum.brightness, 100)
    }

    func testConfigurationClampsUnsafeHardwareTestValues() throws {
        let configuration = KeyLightHardwareTestConfiguration(
            settleInterval: .infinity,
            sampleCount: 0,
            sampleInterval: -1,
            tolerance: .nan
        )

        XCTAssertEqual(configuration.settleInterval, 1)
        XCTAssertEqual(configuration.sampleCount, 1)
        XCTAssertEqual(configuration.sampleInterval, 0.1)
        XCTAssertEqual(configuration.tolerance, 0.05)

        let decoded = try JSONDecoder().decode(
            KeyLightHardwareTestConfiguration.self,
            from: Data(#"{}"#.utf8)
        )
        XCTAssertEqual(decoded, KeyLightHardwareTestConfiguration())
    }

    func testEvaluatorAcceptsAHealthyMonotonicRun() {
        XCTAssertTrue(KeyLightHardwareTestEvaluator.failures(in: healthyObservations()).isEmpty)
    }

    func testEvaluatorRequiresTheUserZeroStateToBeOff() {
        var observations = healthyObservations()
        observations[1] = observation(.zeroBrightness, on: true, luminance: 0.02)

        XCTAssertTrue(KeyLightHardwareTestEvaluator.failures(in: observations)
            .contains("Unexpected power state at brightness-zero"))
    }

    func testEvaluatorChecksThatUserZeroMatchesPowerOff() {
        var observations = healthyObservations()
        observations[1] = observation(.zeroBrightness, on: false, luminance: 0.2)

        XCTAssertTrue(KeyLightHardwareTestEvaluator.failures(in: observations)
            .contains("User 0% does not match power off"))
    }

    func testEvaluatorChecksMonotonicBrightness() {
        var observations = healthyObservations()
        observations[2] = observation(.minimumOn, on: true, luminance: 0.7)
        observations[3] = observation(.midpoint, on: true, luminance: 0.4)

        XCTAssertTrue(KeyLightHardwareTestEvaluator.failures(in: observations)
            .contains("Midpoint is darker than minimum on"))
    }

    func testEvaluatorRequiresAVisibleMaximum() {
        var observations = healthyObservations()
        observations[4] = observation(.maximumOn, on: true, luminance: 0.04)

        XCTAssertTrue(KeyLightHardwareTestEvaluator.failures(in: observations)
            .contains("Maximum on is not brighter than power off"))
    }

    func testEvaluatorAcceptsTheZeroBrightnessToleranceBoundary() {
        var observations = healthyObservations()
        observations[1] = observation(.zeroBrightness, on: false, luminance: 0.07)

        XCTAssertFalse(KeyLightHardwareTestEvaluator.failures(in: observations)
            .contains("User 0% does not match power off"))
    }

    func testEvaluatorAllowsMinimumOnWithinTheTolerance() {
        var observations = healthyObservations()
        observations[0] = observation(.powerOff, on: false, luminance: 0.10)
        observations[1] = observation(.zeroBrightness, on: false, luminance: 0.10)
        observations[2] = observation(.minimumOn, on: true, luminance: 0.05)

        XCTAssertFalse(KeyLightHardwareTestEvaluator.failures(in: observations)
            .contains("Minimum on is darker than power off"))
    }

    func testEvaluatorAllowsMidpointWithinTheTolerance() {
        var observations = healthyObservations()
        observations[2] = observation(.minimumOn, on: true, luminance: 0.20)
        observations[3] = observation(.midpoint, on: true, luminance: 0.15)

        XCTAssertFalse(KeyLightHardwareTestEvaluator.failures(in: observations)
            .contains("Midpoint is darker than minimum on"))
    }

    func testEvaluatorAllowsMaximumWithinTheTolerance() {
        var observations = healthyObservations()
        observations[3] = observation(.midpoint, on: true, luminance: 0.50)
        observations[4] = observation(.maximumOn, on: true, luminance: 0.45)

        XCTAssertFalse(KeyLightHardwareTestEvaluator.failures(in: observations)
            .contains("Maximum on is darker than midpoint"))
    }

    func testEvaluatorTreatsTheMaximumVisibilityThresholdAsAFailure() {
        var observations = healthyObservations()
        observations[4] = observation(.maximumOn, on: true, luminance: 0.07)

        XCTAssertTrue(KeyLightHardwareTestEvaluator.failures(in: observations)
            .contains("Maximum on is not brighter than power off"))
    }

    func testEvaluatorReportsMissingAndNonFiniteObservations() {
        var observations = healthyObservations()
        observations.removeLast()
        observations[0] = observation(.powerOff, on: false, luminance: .nan)

        let failures = KeyLightHardwareTestEvaluator.failures(in: observations)
        XCTAssertTrue(failures.contains("Missing observation: maximum-on"))

        let completeFailures = KeyLightHardwareTestEvaluator.failures(in: healthyObservations()
            .map { $0.step == .midpoint ? observation(.midpoint, on: true, luminance: .nan) : $0 })
        XCTAssertTrue(completeFailures.contains("Non-finite luminance at midpoint"))
    }

    private func healthyObservations() -> [KeyLightHardwareObservation] {
        [
            observation(.powerOff, on: false, luminance: 0.02),
            observation(.zeroBrightness, on: false, luminance: 0.02),
            observation(.minimumOn, on: true, luminance: 0.20),
            observation(.midpoint, on: true, luminance: 0.50),
            observation(.maximumOn, on: true, luminance: 0.90)
        ]
    }

    private func observation(_ step: KeyLightHardwareTestStep,
                             on: Bool,
                             luminance: Double) -> KeyLightHardwareObservation {
        KeyLightHardwareObservation(
            step: step,
            confirmedState: KeyLightState(isOn: on, brightness: on ? 50 : 0, temperature: 4_200),
            measuredLuminance: luminance
        )
    }
}
