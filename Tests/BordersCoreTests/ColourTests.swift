import CoreGraphics
import XCTest
@testable import BordersCore

final class ColourTests: XCTestCase {
    func testPackedValueSplitsIntoChannels() {
        let colour = RGBA(packed: 0xff33_6699)
        XCTAssertEqual(colour.red, CGFloat(0x33) / 255, accuracy: 1e-9)
        XCTAssertEqual(colour.green, CGFloat(0x66) / 255, accuracy: 1e-9)
        XCTAssertEqual(colour.blue, CGFloat(0x99) / 255, accuracy: 1e-9)
        XCTAssertEqual(colour.alpha, 1, accuracy: 1e-9)
    }

    func testChannelsDoNotBleedIntoEachOther() {
        XCTAssertEqual(RGBA(packed: 0x0000_00ff), RGBA(red: 0, green: 0, blue: 1, alpha: 0))
        XCTAssertEqual(RGBA(packed: 0x00ff_0000), RGBA(red: 1, green: 0, blue: 0, alpha: 0))
        XCTAssertEqual(RGBA(packed: 0x0000_ff00), RGBA(red: 0, green: 1, blue: 0, alpha: 0))
    }

    func testPackedAlphaScalesTheRequestedAlpha() {
        XCTAssertEqual(RGBA(packed: 0x8000_0000, alpha: 0.5).alpha,
                       0.5 * CGFloat(0x80) / 255, accuracy: 1e-9)
    }

    func testAlphaIsClampedToZeroThroughOne() {
        XCTAssertEqual(RGBA(packed: 0xff00_0000, alpha: 4).alpha, 1)
        XCTAssertEqual(RGBA(packed: 0xff00_0000, alpha: -1).alpha, 0)
        XCTAssertEqual(RGBA.white(alpha: 9).alpha, 1)
        XCTAssertEqual(RGBA.white(alpha: -9).alpha, 0)
    }

    func testNotANumberAlphaBecomesTransparent() {
        XCTAssertEqual(RGBA.clamped(.nan), 0)
    }

    func testWhiteIsFullyWhite() {
        let white = RGBA.white(alpha: 0.25)
        XCTAssertEqual(white, RGBA(red: 1, green: 1, blue: 1, alpha: 0.25))
    }
}
