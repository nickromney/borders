import CoreGraphics
import Foundation

/// A colour as straight (non-premultiplied) components in 0...1.
public struct RGBA: Equatable, Sendable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Decompose a packed `0xAARRGGBB` value, scaling its alpha by `alpha`.
    public init(packed value: UInt32, alpha: CGFloat = 1) {
        self.init(red: RGBA.channel(value >> 16),
                  green: RGBA.channel(value >> 8),
                  blue: RGBA.channel(value),
                  alpha: RGBA.clamped(alpha * RGBA.channel(value >> 24)))
    }

    public static func white(alpha: CGFloat) -> RGBA {
        RGBA(red: 1, green: 1, blue: 1, alpha: clamped(alpha))
    }

    static func channel(_ value: UInt32) -> CGFloat {
        CGFloat(value & 255) / 255
    }

    public static func clamped(_ value: CGFloat) -> CGFloat {
        guard !value.isNaN else { return 0 }
        return min(1, max(0, value))
    }
}
