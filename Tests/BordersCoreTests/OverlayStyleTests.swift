import CoreGraphics
import XCTest
@testable import BordersCore

final class OverlayStyleTests: XCTestCase {
    func testQuietStyleDrawsOneSolidRing() {
        let style = OverlayStyle.make(width: 5, brightness: 1, tint: 0xff00_ff00, glowing: false)
        XCTAssertEqual(style.glow, .hidden)
        XCTAssertEqual(style.bloom, .hidden)
        XCTAssertEqual(style.highlight, .hidden)
        XCTAssertEqual(style.core.lineWidth, 5)
        XCTAssertEqual(style.core.stroke, RGBA(red: 0, green: 1, blue: 0, alpha: 1))
        XCTAssertEqual(style.core.shadowOpacity, 0)
    }

    func testQuietStyleFollowsBrightness() {
        let style = OverlayStyle.make(width: 5, brightness: 0.5, tint: 0xff00_ff00, glowing: false)
        XCTAssertEqual(style.core.stroke.alpha, 0.5, accuracy: 1e-9)
    }

    func testGlowingStyleDrawsFourRings() {
        let style = OverlayStyle.make(width: 10, brightness: 1, tint: 0xffff_ffff, glowing: true)
        XCTAssertEqual(style.layers.count, 4)
        XCTAssertTrue(style.layers.allSatisfy { $0.lineWidth > 0 })
    }

    func testGlowingRingsWidenOutwards() {
        let style = OverlayStyle.make(width: 10, brightness: 1, tint: 0xffff_ffff, glowing: true)
        XCTAssertEqual(style.glow.lineWidth, 22, accuracy: 1e-9)
        XCTAssertEqual(style.bloom.lineWidth, 13.5, accuracy: 1e-9)
        XCTAssertEqual(style.core.lineWidth, 10)
        XCTAssertGreaterThan(style.glow.lineWidth, style.bloom.lineWidth)
        XCTAssertGreaterThan(style.bloom.lineWidth, style.core.lineWidth)
        XCTAssertGreaterThan(style.core.lineWidth, style.highlight.lineWidth)
    }

    func testHighlightNeverGetsThinnerThanAHairline() {
        let thin = OverlayStyle.make(width: 8, brightness: 1, tint: 0xffff_ffff, glowing: true)
        XCTAssertEqual(thin.highlight.lineWidth, 1.5)
        let wide = OverlayStyle.make(width: 40, brightness: 1, tint: 0xffff_ffff, glowing: true)
        XCTAssertEqual(wide.highlight.lineWidth, 7.2, accuracy: 1e-9)
    }

    func testShadowsAndStrokesScaleWithBrightness() {
        let full = OverlayStyle.make(width: 10, brightness: 1, tint: 0xffff_ffff, glowing: true)
        let half = OverlayStyle.make(width: 10, brightness: 0.5, tint: 0xffff_ffff, glowing: true)
        for (bright, dim) in zip(full.layers, half.layers) where bright.shadowOpacity > 0 {
            XCTAssertEqual(dim.shadowOpacity, bright.shadowOpacity / 2, accuracy: 1e-9)
        }
        XCTAssertEqual(half.core.stroke.alpha, full.core.stroke.alpha / 2, accuracy: 1e-9)
    }

    func testBrightnessOutOfRangeIsClamped() {
        let over = OverlayStyle.make(width: 10, brightness: 4, tint: 0xffff_ffff, glowing: true)
        XCTAssertEqual(over, OverlayStyle.make(width: 10, brightness: 1, tint: 0xffff_ffff, glowing: true))
        let under = OverlayStyle.make(width: 10, brightness: -1, tint: 0xffff_ffff, glowing: true)
        XCTAssertTrue(under.layers.allSatisfy { $0.shadowOpacity == 0 && $0.stroke.alpha == 0 })
    }

    func testGlowingShadowColoursAreFullyOpaque() {
        let style = OverlayStyle.make(width: 10, brightness: 0.2, tint: 0xffab_cdef, glowing: true)
        XCTAssertEqual(style.glow.shadowColor.alpha, 1)
        XCTAssertEqual(style.highlight.shadowColor, .white(alpha: 1))
    }

    func testHiddenLayerDrawsNothing() {
        XCTAssertEqual(LayerStyle.hidden.lineWidth, 0)
        XCTAssertEqual(LayerStyle.hidden.stroke.alpha, 0)
        XCTAssertEqual(LayerStyle.hidden.shadowOpacity, 0)
        XCTAssertEqual(LayerStyle.hidden.shadowRadius, 0)
    }
}

final class OverlayGeometryTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 200, width: 800, height: 600)

    func testQuietGeometryUsesTheFrameUnpadded() {
        let geometry = OverlayGeometry.make(frame: frame, width: 4, radius: 10, glowing: false)
        XCTAssertEqual(geometry.windowFrame, frame)
        XCTAssertEqual(geometry.bounds, CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(geometry.pathRect, CGRect(x: 2, y: 2, width: 796, height: 596))
    }

    func testGlowingGeometryPadsTheWindowOutwards() {
        let geometry = OverlayGeometry.make(frame: frame, width: 4, radius: 10, glowing: true)
        XCTAssertEqual(geometry.windowFrame, CGRect(x: 36, y: 136, width: 928, height: 728))
        XCTAssertEqual(geometry.pathRect, CGRect(x: 66, y: 66, width: 796, height: 596))
    }

    func testTheStrokedPathStaysCentredOnTheRequestedFrame() {
        let geometry = OverlayGeometry.make(frame: frame, width: 0, radius: 0, glowing: true)
        XCTAssertEqual(geometry.pathRect.width, frame.width)
        XCTAssertEqual(geometry.pathRect.origin.x, OverlayGeometry.glowPadding)
        XCTAssertEqual(geometry.pathRect.origin.y, OverlayGeometry.glowPadding)
    }

    func testNegativeRadiusIsFlattenedToSquareCorners() {
        XCTAssertEqual(OverlayGeometry.make(frame: frame, width: 4, radius: -5, glowing: false).cornerRadius, 0)
        XCTAssertEqual(OverlayGeometry.make(frame: frame, width: 4, radius: 18, glowing: false).cornerRadius, 18)
    }
}
