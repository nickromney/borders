import CoreGraphics
import XCTest
@testable import BordersCore

final class SettingsTests: XCTestCase {
    func testClampHoldsTheRange() {
        XCTAssertEqual(Settings.clamp(-1, to: 0...1), 0)
        XCTAssertEqual(Settings.clamp(2, to: 0...1), 1)
        XCTAssertEqual(Settings.clamp(0.5, to: 0...1), 0.5)
        XCTAssertEqual(Settings.clamp(0, to: 0...1), 0)
        XCTAssertEqual(Settings.clamp(1, to: 0...1), 1)
    }

    func testClampTreatsNotANumberAsTheLowerBound() {
        XCTAssertEqual(Settings.clamp(.nan, to: 8...40), 8)
    }

    func testWidthIsClampedToTheMenuRange() {
        var settings = Settings()
        settings.setWidth(1)
        XCTAssertEqual(settings.width, 8)
        settings.setWidth(1000)
        XCTAssertEqual(settings.width, 40)
        settings.setWidth(16)
        XCTAssertEqual(settings.width, 16)
    }

    func testBrightnessIsClampedToZeroThroughOne() {
        var settings = Settings()
        settings.setBrightness(-3)
        XCTAssertEqual(settings.brightness, 0)
        settings.setBrightness(5)
        XCTAssertEqual(settings.brightness, 1)
        settings.setBrightness(0.25)
        XCTAssertEqual(settings.brightness, 0.25)
    }

    func testStatusLineReportsEverySetting() {
        var settings = Settings(mode: .ringLight, display: .all, width: 24, brightness: 0.5, neon: true)
        XCTAssertEqual(settings.statusLine(boundAppBundleID: "com.apple.Safari"),
                       "mode=ringLight display=all width=24 brightness=50 neon=on app=com.apple.Safari")
        settings.neon = false
        settings.mode = .off
        XCTAssertEqual(settings.statusLine(boundAppBundleID: nil),
                       "mode=off display=all width=24 brightness=50 neon=off app=any")
    }

    func testStatusLineTruncatesRatherThanRounds() {
        let settings = Settings(width: 15.9, brightness: 0.759)
        XCTAssertEqual(settings.statusLine(boundAppBundleID: nil),
                       "mode=off display=main width=15 brightness=75 neon=on app=any")
    }

    func testResolveUsesBuiltInDefaultsWhenNothingIsStored() {
        let settings = SettingsResolver.resolve(stored: StoredSettings(),
                                                configuration: Configuration(color: 0xdead_beef))
        XCTAssertEqual(settings.mode, .off)
        XCTAssertEqual(settings.display, .main)
        XCTAssertEqual(settings.width, 24)
        XCTAssertEqual(settings.brightness, 1)
        XCTAssertEqual(settings.tint, 0xdead_beef)
        XCTAssertTrue(settings.neon)
    }

    func testResolvePrefersStoredValues() {
        let stored = StoredSettings(mode: "focused", display: "all", width: 16,
                                    brightness: 0.25, tint: 0x0011_2233, neon: false)
        let settings = SettingsResolver.resolve(stored: stored, configuration: Configuration())
        XCTAssertEqual(settings.mode, .focused)
        XCTAssertEqual(settings.display, .all)
        XCTAssertEqual(settings.width, 16)
        XCTAssertEqual(settings.brightness, 0.25)
        XCTAssertEqual(settings.tint, 0x0011_2233)
        XCTAssertFalse(settings.neon)
    }

    func testResolveFallsBackWhenStoredNamesAreUnknown() {
        let stored = StoredSettings(mode: "sparkle", display: "elsewhere")
        let settings = SettingsResolver.resolve(stored: stored, configuration: Configuration())
        XCTAssertEqual(settings.mode, .off)
        XCTAssertEqual(settings.display, .main)
    }

    func testResolveClampsStoredValuesOutOfRange() {
        let stored = StoredSettings(width: 400, brightness: 12)
        let settings = SettingsResolver.resolve(stored: stored, configuration: Configuration())
        XCTAssertEqual(settings.width, 40)
        XCTAssertEqual(settings.brightness, 1)
    }

    func testResolveSurvivesANegativeStoredTint() {
        let settings = SettingsResolver.resolve(stored: StoredSettings(tint: -1),
                                                configuration: Configuration())
        XCTAssertEqual(settings.tint, 0xffff_ffff)
    }

    func testModeAndDisplayRawValuesAreStable() {
        XCTAssertEqual(Mode.allCases.map(\.rawValue), ["off", "focused", "ringLight"])
        XCTAssertEqual(DisplayChoice.allCases.map(\.rawValue), ["main", "focused", "all"])
    }
}
