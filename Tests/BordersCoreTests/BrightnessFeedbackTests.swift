import Foundation
import XCTest
@testable import BordersCore

final class BrightnessFeedbackTests: XCTestCase {
    func testSliderWritesWaitForTheHardwareSettleWindow() {
        XCTAssertEqual(KeyLightTiming.sliderWriteDebounce, 0.3, accuracy: 0.000_001)
    }

    func testLuminanceUsesPerceptualRGBWeights() {
        let samples = [
            RGBSample(red: 1, green: 0, blue: 0),
            RGBSample(red: 0, green: 1, blue: 0),
            RGBSample(red: 0, green: 0, blue: 1)
        ]

        XCTAssertEqual(LuminanceMeasurement.mean(of: samples)!, (0.2126 + 0.7152 + 0.0722) / 3, accuracy: 0.000_001)
    }

    func testLuminanceRejectsAnEmptyFrame() {
        XCTAssertNil(LuminanceMeasurement.mean(of: []))
    }

    func testLuminanceNormalizesVideoAndFullRangeCameraValues() {
        XCTAssertEqual(LuminanceMeasurement.normalizedVideoRangeLuma(16), 0)
        XCTAssertEqual(LuminanceMeasurement.normalizedVideoRangeLuma(235), 1)
        XCTAssertEqual(LuminanceMeasurement.normalizedVideoRangeLuma(0), 0)
        XCTAssertEqual(LuminanceMeasurement.normalizedFullRangeLuma(255), 1)
        XCTAssertEqual(LuminanceMeasurement.normalizedFullRangeLuma(.nan), 0)
    }

    func testDefaultFeedbackConfigurationLocksExposure() {
        XCTAssertTrue(BrightnessFeedbackConfiguration().locksCameraExposure)
    }

    func testFeedbackConfigurationClampsUnsafeValues() {
        let configuration = BrightnessFeedbackConfiguration(
            targetLuminance: -1,
            deadband: 0,
            sampleCount: 0,
            cooldown: -1,
            maximumStep: 0,
            sampleInterval: 0
        )

        XCTAssertEqual(configuration.targetLuminance, 0)
        XCTAssertEqual(configuration.deadband, 0.01)
        XCTAssertEqual(configuration.sampleCount, 1)
        XCTAssertEqual(configuration.cooldown, 0)
        XCTAssertEqual(configuration.maximumStep, 1)
        XCTAssertEqual(configuration.sampleInterval, 0.1)
    }

    func testDecodedConfigurationDefaultsExposureLockWhenTheFieldIsMissing() throws {
        let configuration = try JSONDecoder().decode(
            BrightnessFeedbackConfiguration.self,
            from: Data(#"{}"#.utf8)
        )

        XCTAssertTrue(configuration.locksCameraExposure)
    }

    func testRGBSamplesClampOutOfRangeAndNonFiniteValues() {
        let sample = RGBSample(red: -1, green: 2, blue: .infinity)

        XCTAssertEqual(sample, RGBSample(red: 0, green: 1, blue: 0))
    }

    func testFeedbackWaitsForAStableSampleWindow() {
        var policy = BrightnessFeedbackPolicy(configuration: configuration())
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertNil(policy.nextBrightness(for: 0.9, currentBrightness: 60, at: now))
        XCTAssertEqual(policy.nextBrightness(for: 0.9, currentBrightness: 60, at: now), 56)
    }

    func testBrightReadingReducesBrightnessByTheConfiguredMaximumStep() {
        var policy = BrightnessFeedbackPolicy(configuration: configuration())
        let now = Date(timeIntervalSince1970: 100)

        _ = policy.nextBrightness(for: 0.9, currentBrightness: 60, at: now)
        XCTAssertEqual(policy.nextBrightness(for: 0.9, currentBrightness: 60, at: now), 56)
    }

    func testDarkReadingIncreasesBrightnessByTheConfiguredMaximumStep() {
        var policy = BrightnessFeedbackPolicy(configuration: configuration())
        let now = Date(timeIntervalSince1970: 100)

        _ = policy.nextBrightness(for: 0.1, currentBrightness: 60, at: now)
        XCTAssertEqual(policy.nextBrightness(for: 0.1, currentBrightness: 60, at: now), 64)
    }

    func testDeadbandPreventsSmallAdjustments() {
        var policy = BrightnessFeedbackPolicy(configuration: configuration())
        let now = Date(timeIntervalSince1970: 100)

        _ = policy.nextBrightness(for: 0.52, currentBrightness: 60, at: now)
        XCTAssertNil(policy.nextBrightness(for: 0.52, currentBrightness: 60, at: now))
    }

    func testCooldownPreventsRapidAdjustments() {
        var policy = BrightnessFeedbackPolicy(configuration: configuration())
        let first = Date(timeIntervalSince1970: 100)

        _ = policy.nextBrightness(for: 0.9, currentBrightness: 60, at: first)
        XCTAssertEqual(policy.nextBrightness(for: 0.9, currentBrightness: 60, at: first), 56)
        XCTAssertNil(policy.nextBrightness(for: 0.1, currentBrightness: 56, at: first.addingTimeInterval(1)))
        XCTAssertEqual(policy.nextBrightness(for: 0.1, currentBrightness: 56, at: first.addingTimeInterval(1.5)), 60)
    }

    func testFeedbackDoesNotMoveBeyondTheBrightnessLimits() {
        var policy = BrightnessFeedbackPolicy(configuration: configuration())
        let now = Date(timeIntervalSince1970: 100)

        _ = policy.nextBrightness(for: 0.9, currentBrightness: KeyLightLimits.minimumVisibleBrightness, at: now)
        XCTAssertNil(policy.nextBrightness(for: 0.9, currentBrightness: KeyLightLimits.minimumVisibleBrightness, at: now))

        policy.reset()
        _ = policy.nextBrightness(for: 0.1, currentBrightness: 100, at: now)
        XCTAssertNil(policy.nextBrightness(for: 0.1, currentBrightness: 100, at: now))
    }

    func testDeadbandIncludesItsExactBoundary() {
        var policy = BrightnessFeedbackPolicy(configuration: BrightnessFeedbackConfiguration(
            targetLuminance: 0.5,
            deadband: 0.25,
            sampleCount: 2,
            cooldown: 0,
            maximumStep: 4,
            sampleInterval: 0.5
        ))
        let now = Date(timeIntervalSince1970: 100)

        _ = policy.nextBrightness(for: 0.75, currentBrightness: 60, at: now)
        XCTAssertNil(policy.nextBrightness(for: 0.75, currentBrightness: 60, at: now))
    }

    func testInvalidLuminanceDoesNotConsumeTheSampleWindow() {
        var policy = BrightnessFeedbackPolicy(configuration: configuration())
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertNil(policy.nextBrightness(for: .nan, currentBrightness: 60, at: now))
        XCTAssertNil(policy.nextBrightness(for: 0.9, currentBrightness: 60, at: now))
        XCTAssertEqual(policy.nextBrightness(for: 0.9, currentBrightness: 60, at: now), 56)
    }

    func testCameraSelectionPrefersTheDocCamOverLogitech() {
        let devices = [
            BrightnessCameraCandidate(id: "logitech", name: "Logitech C920", isExternal: true),
            BrightnessCameraCandidate(id: "doccam", name: "USB Camera", isExternal: true),
            BrightnessCameraCandidate(id: "built-in", name: "FaceTime HD Camera", isExternal: false)
        ]

        XCTAssertEqual(BrightnessCameraSelectionPolicy.sortedByPreference(devices).map(\.id), ["doccam", "logitech", "built-in"])
    }

    func testCameraSelectionUsesAlphabeticalOrderForEqualPreferences() {
        let devices = [
            BrightnessCameraCandidate(id: "zeta", name: "Zeta Camera", isExternal: true),
            BrightnessCameraCandidate(id: "alpha", name: "Alpha Camera", isExternal: true)
        ]

        XCTAssertEqual(BrightnessCameraSelectionPolicy.sortedByPreference(devices).map(\.id), ["alpha", "zeta"])
    }

    func testWriteCoalescerKeepsOnlyTheLatestValuePerDevice() {
        var coalescer = KeyLightWriteCoalescer()
        let first = KeyLightState(isOn: true, brightness: 60, temperature: 4_200)
        let latest = first.changing(brightness: 0)

        coalescer.replace(first, for: "one")
        coalescer.replace(latest, for: "one")
        coalescer.replace(first, for: "two")

        XCTAssertEqual(coalescer.takeLatest(for: "one"), latest)
        XCTAssertEqual(coalescer.takeLatest(for: "two"), first)
        XCTAssertTrue(coalescer.isEmpty)
    }

    func testWriteCoalescerCanCancelOneDeviceWithoutAffectingAnother() {
        var coalescer = KeyLightWriteCoalescer()
        let state = KeyLightState.sensibleDefault

        coalescer.replace(state, for: "one")
        coalescer.replace(state, for: "two")
        coalescer.remove(for: "one")

        XCTAssertNil(coalescer.takeLatest(for: "one"))
        XCTAssertEqual(coalescer.takeLatest(for: "two"), state)
    }

    private func configuration() -> BrightnessFeedbackConfiguration {
        BrightnessFeedbackConfiguration(
            targetLuminance: 0.5,
            deadband: 0.04,
            sampleCount: 2,
            cooldown: 1.5,
            maximumStep: 4,
            sampleInterval: 0.5
        )
    }
}
