import XCTest
@testable import BordersCore

final class CameraCaptureFormatTests: XCTestCase {
    func testPrefersTheLargestUsableFormat() {
        let candidates = [
            CameraCaptureFormatCandidate(width: 1_920, height: 1_080, maxFrameRate: 30),
            CameraCaptureFormatCandidate(width: 3_840, height: 3_024, maxFrameRate: 15),
            CameraCaptureFormatCandidate(width: 2_560, height: 1_440, maxFrameRate: 30)
        ]

        XCTAssertEqual(CameraCaptureFormatPolicy.preferredIndex(in: candidates), 1)
    }

    func testPrefersFrameRateWhenPixelCountMatches() {
        let candidates = [
            CameraCaptureFormatCandidate(width: 1_920, height: 1_080, maxFrameRate: 30, pixelFormatScore: 1),
            CameraCaptureFormatCandidate(width: 1_920, height: 1_080, maxFrameRate: 15, pixelFormatScore: 3)
        ]

        XCTAssertEqual(CameraCaptureFormatPolicy.preferredIndex(in: candidates), 0)
    }

    func testPrefersPixelFormatWhenSizeAndFrameRateMatch() {
        let candidates = [
            CameraCaptureFormatCandidate(width: 3_840, height: 3_024, maxFrameRate: 15, pixelFormatScore: 1),
            CameraCaptureFormatCandidate(width: 3_840, height: 3_024, maxFrameRate: 15, pixelFormatScore: 3)
        ]

        XCTAssertEqual(CameraCaptureFormatPolicy.preferredIndex(in: candidates), 1)
    }

    func testKeepsTheFirstFormatWhenCandidatesAreEquivalent() {
        let candidate = CameraCaptureFormatCandidate(width: 1_920, height: 1_080, maxFrameRate: 30)

        XCTAssertEqual(CameraCaptureFormatPolicy.preferredIndex(in: [candidate, candidate]), 0)
    }

    func testIgnoresInvalidFormats() {
        let candidates = [
            CameraCaptureFormatCandidate(width: 0, height: 1_080, maxFrameRate: 30),
            CameraCaptureFormatCandidate(width: 1_920, height: 0, maxFrameRate: 30),
            CameraCaptureFormatCandidate(width: 1_920, height: 1_080, maxFrameRate: 0),
            CameraCaptureFormatCandidate(width: 1_920, height: 1_080, maxFrameRate: .nan),
            CameraCaptureFormatCandidate(width: 640, height: 480, maxFrameRate: 30)
        ]

        XCTAssertEqual(CameraCaptureFormatPolicy.preferredIndex(in: candidates), 4)
    }

    func testReturnsNilWhenNoFormatIsUsable() {
        let candidates = [
            CameraCaptureFormatCandidate(width: 0, height: 480, maxFrameRate: 30),
            CameraCaptureFormatCandidate(width: 640, height: 0, maxFrameRate: 30),
            CameraCaptureFormatCandidate(width: -1, height: 480, maxFrameRate: 30),
            CameraCaptureFormatCandidate(width: 640, height: 480, maxFrameRate: .infinity)
        ]

        XCTAssertNil(CameraCaptureFormatPolicy.preferredIndex(in: candidates))
    }

    func testAcceptsTheMinimumUsableFrameRate() {
        let candidate = CameraCaptureFormatCandidate(width: 640, height: 480, maxFrameRate: 1)

        XCTAssertEqual(CameraCaptureFormatPolicy.preferredIndex(in: [candidate]), 0)
    }
}
