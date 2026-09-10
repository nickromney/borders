import CoreGraphics
import XCTest
@testable import BordersCore

private func windowInfo(pid: pid_t = 42, layer: Int = 0, alpha: CGFloat? = 1,
                        x: CGFloat = 0, y: CGFloat = 0,
                        width: CGFloat = 800, height: CGFloat = 600) -> [String: Any] {
    var item: [String: Any] = [
        kCGWindowOwnerPID as String: pid,
        kCGWindowLayer as String: layer,
        kCGWindowBounds as String: ["X": x, "Y": y, "Width": width, "Height": height]
    ]
    if let alpha { item[kCGWindowAlpha as String] = alpha }
    return item
}

final class WindowSelectionTests: XCTestCase {
    func testAcceptsAPlainVisibleWindow() {
        XCTAssertEqual(WindowSelection.quartzFrame(from: windowInfo(), pid: 42),
                       CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    func testRejectsAnotherApplicationsWindow() {
        XCTAssertNil(WindowSelection.quartzFrame(from: windowInfo(pid: 7), pid: 42))
    }

    func testRejectsWindowsAboveTheNormalLayer() {
        XCTAssertNil(WindowSelection.quartzFrame(from: windowInfo(layer: 25), pid: 42))
    }

    func testRejectsFullyTransparentWindows() {
        XCTAssertNil(WindowSelection.quartzFrame(from: windowInfo(alpha: 0), pid: 42))
        XCTAssertNotNil(WindowSelection.quartzFrame(from: windowInfo(alpha: 0.1), pid: 42))
    }

    func testAssumesOpaqueWhenAlphaIsMissing() {
        XCTAssertNotNil(WindowSelection.quartzFrame(from: windowInfo(alpha: nil), pid: 42))
    }

    func testRejectsWindowsAtOrBelowTheMinimumSide() {
        XCTAssertNil(WindowSelection.quartzFrame(from: windowInfo(width: 60), pid: 42))
        XCTAssertNil(WindowSelection.quartzFrame(from: windowInfo(height: 60), pid: 42))
        XCTAssertNotNil(WindowSelection.quartzFrame(from: windowInfo(width: 61, height: 61), pid: 42))
    }

    func testRejectsAnEntryWithoutUsableBounds() {
        var item = windowInfo()
        item[kCGWindowBounds as String] = ["X": CGFloat(0), "Y": CGFloat(0), "Width": CGFloat(100)]
        XCTAssertNil(WindowSelection.quartzFrame(from: item, pid: 42))
        item[kCGWindowBounds as String] = "not a dictionary"
        XCTAssertNil(WindowSelection.quartzFrame(from: item, pid: 42))
    }

    func testPrimaryPrefersTheLargestWindow() {
        let small = WindowCandidate(order: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let large = WindowCandidate(order: 3, frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        XCTAssertEqual(WindowSelection.primary(among: [small, large]), large)
        XCTAssertEqual(WindowSelection.primary(among: [large, small]), large)
    }

    func testEqualAreasAreBrokenByFrontToBackOrder() {
        let front = WindowCandidate(order: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let back = WindowCandidate(order: 5, frame: CGRect(x: 50, y: 50, width: 100, height: 100))
        XCTAssertEqual(WindowSelection.primary(among: [back, front]), front)
        XCTAssertEqual(WindowSelection.primary(among: [front, back]), front)
    }

    func testPrimaryOfNothingIsNothing() {
        XCTAssertNil(WindowSelection.primary(among: []))
    }

    func testCocoaRectFlipsAroundTheMainDisplayTop() {
        let quartz = CGRect(x: 10, y: 100, width: 400, height: 300)
        XCTAssertEqual(WindowSelection.cocoaRect(quartz, mainTop: 1000),
                       CGRect(x: 10, y: 600, width: 400, height: 300))
    }

    func testCocoaRectRoundTripsBackToQuartz() {
        let quartz = CGRect(x: 10, y: 100, width: 400, height: 300)
        let cocoa = WindowSelection.cocoaRect(quartz, mainTop: 1000)
        XCTAssertEqual(WindowSelection.cocoaRect(cocoa, mainTop: 1000), quartz)
    }

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testFullHeightWindowAtTheBottomIsFullscreen() {
        XCTAssertTrue(WindowSelection.isFullscreen(screen, screens: [screen]))
    }

    func testWindowShorterThanTheToleranceIsNotFullscreen() {
        let short = CGRect(x: 0, y: 0, width: 1920, height: 1080 - 9)
        XCTAssertFalse(WindowSelection.isFullscreen(short, screens: [screen]))
        let justTall = CGRect(x: 0, y: 0, width: 1920, height: 1080 - 8)
        XCTAssertTrue(WindowSelection.isFullscreen(justTall, screens: [screen]))
    }

    func testWindowLiftedAboveTheScreenBottomIsNotFullscreen() {
        let lifted = CGRect(x: 0, y: 9, width: 1920, height: 1080)
        XCTAssertFalse(WindowSelection.isFullscreen(lifted, screens: [screen]))
        let nudged = CGRect(x: 0, y: 8, width: 1920, height: 1080)
        XCTAssertTrue(WindowSelection.isFullscreen(nudged, screens: [screen]))
    }

    func testFullscreenIsCheckedAgainstEveryScreen() {
        let second = CGRect(x: 1920, y: 0, width: 1000, height: 500)
        XCTAssertTrue(WindowSelection.isFullscreen(second, screens: [screen, second]))
        XCTAssertFalse(WindowSelection.isFullscreen(second, screens: []))
    }

    private let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080),
                           CGRect(x: 1920, y: 0, width: 1280, height: 800)]

    func testAllChoiceCoversEveryScreen() {
        XCTAssertEqual(WindowSelection.screenIndices(for: .all, screens: screens,
                                                     mainIndex: 0, focusedFrame: nil), [0, 1])
    }

    func testMainChoiceCoversOnlyTheMainScreen() {
        XCTAssertEqual(WindowSelection.screenIndices(for: .main, screens: screens,
                                                     mainIndex: 1, focusedFrame: nil), [1])
        XCTAssertEqual(WindowSelection.screenIndices(for: .main, screens: screens,
                                                     mainIndex: nil, focusedFrame: nil), [])
    }

    func testFocusedChoiceCoversTheScreensTheWindowTouches() {
        let onSecond = CGRect(x: 2000, y: 100, width: 400, height: 300)
        XCTAssertEqual(WindowSelection.screenIndices(for: .focused, screens: screens,
                                                     mainIndex: 0, focusedFrame: onSecond), [1])
        let spanning = CGRect(x: 1800, y: 100, width: 400, height: 300)
        XCTAssertEqual(WindowSelection.screenIndices(for: .focused, screens: screens,
                                                     mainIndex: 0, focusedFrame: spanning), [0, 1])
    }

    func testFocusedChoiceFallsBackToTheMainScreen() {
        XCTAssertEqual(WindowSelection.screenIndices(for: .focused, screens: screens,
                                                     mainIndex: 1, focusedFrame: nil), [1])
        XCTAssertEqual(WindowSelection.screenIndices(for: .focused, screens: screens,
                                                     mainIndex: nil, focusedFrame: nil), [])
    }

    func testFocusedChoiceCoversNothingWhenTheWindowIsOffEveryScreen() {
        let offscreen = CGRect(x: 9000, y: 9000, width: 100, height: 100)
        XCTAssertEqual(WindowSelection.screenIndices(for: .focused, screens: screens,
                                                     mainIndex: 0, focusedFrame: offscreen), [])
    }
}

final class PrimaryWindowTests: XCTestCase {
    private func candidate(order: Int, width: CGFloat, height: CGFloat) -> WindowCandidate {
        WindowCandidate(order: order, frame: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func testAreaIsWidthTimesHeight() {
        XCTAssertEqual(candidate(order: 0, width: 30, height: 20).area, 600)
    }

    func testAreaBeatsAspectRatio() {
        // A tall window has the larger area but the smaller width/height ratio,
        // so only a true area comparison picks it.
        let tall = candidate(order: 1, width: 100, height: 300)
        let wide = candidate(order: 0, width: 400, height: 50)
        XCTAssertGreaterThan(tall.area, wide.area)
        XCTAssertEqual(WindowSelection.primary(among: [wide, tall]), tall)
    }

    func testABiggerWindowBeatsASmallerOne() {
        let big = candidate(order: 9, width: 900, height: 700)
        let small = candidate(order: 0, width: 100, height: 100)
        XCTAssertTrue(WindowSelection.beats(big, small))
        XCTAssertFalse(WindowSelection.beats(small, big))
    }

    func testEqualAreasFallBackToFrontToBackOrder() {
        let front = candidate(order: 0, width: 100, height: 100)
        let back = candidate(order: 5, width: 100, height: 100)
        XCTAssertTrue(WindowSelection.beats(front, back))
        XCTAssertFalse(WindowSelection.beats(back, front))
    }

    func testAnIdenticalCandidateNeverDisplacesTheIncumbent() {
        let first = WindowCandidate(order: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let second = WindowCandidate(order: 2, frame: CGRect(x: 500, y: 500, width: 100, height: 100))
        XCTAssertFalse(WindowSelection.beats(second, first))
        XCTAssertEqual(WindowSelection.primary(among: [first, second]), first)
    }

    func testTheFirstCandidateIsTheStartingIncumbent() {
        let only = candidate(order: 3, width: 200, height: 200)
        XCTAssertEqual(WindowSelection.primary(among: [only]), only)
    }
}
