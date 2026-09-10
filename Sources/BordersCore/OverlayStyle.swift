import CoreGraphics
import Foundation

/// One stroked ring in the overlay stack, from outermost glow to inner highlight.
public struct LayerStyle: Equatable, Sendable {
    public let lineWidth: CGFloat
    public let stroke: RGBA
    public let shadowRadius: CGFloat
    public let shadowOpacity: CGFloat
    public let shadowColor: RGBA

    public init(lineWidth: CGFloat,
                stroke: RGBA,
                shadowRadius: CGFloat,
                shadowOpacity: CGFloat,
                shadowColor: RGBA) {
        self.lineWidth = lineWidth
        self.stroke = stroke
        self.shadowRadius = shadowRadius
        self.shadowOpacity = shadowOpacity
        self.shadowColor = shadowColor
    }

    /// A layer that draws nothing, used to switch a ring off without
    /// removing it from the stack.
    public static let hidden = LayerStyle(lineWidth: 0,
                                          stroke: .white(alpha: 0),
                                          shadowRadius: 0,
                                          shadowOpacity: 0,
                                          shadowColor: .white(alpha: 0))
}

/// The four rings drawn into every overlay window.
public struct OverlayStyle: Equatable, Sendable {
    public let glow: LayerStyle
    public let bloom: LayerStyle
    public let core: LayerStyle
    public let highlight: LayerStyle

    public var layers: [LayerStyle] { [glow, bloom, core, highlight] }

    /// Build the ring stack for one draw.
    ///
    /// The glowing form is the ring light: a bright core over a coloured
    /// multi-layer bloom. The quiet form is the focused-window border, a
    /// single solid stroke with every halo ring switched off.
    public static func make(width: CGFloat, brightness: CGFloat, tint: UInt32, glowing: Bool) -> OverlayStyle {
        let level = RGBA.clamped(brightness)
        guard glowing else {
            return OverlayStyle(glow: .hidden,
                                bloom: .hidden,
                                core: LayerStyle(lineWidth: width,
                                                 stroke: RGBA(packed: tint, alpha: level),
                                                 shadowRadius: 0,
                                                 shadowOpacity: 0,
                                                 shadowColor: .white(alpha: 0)),
                                highlight: .hidden)
        }
        return OverlayStyle(
            glow: LayerStyle(lineWidth: width * 2.2,
                             stroke: RGBA(packed: tint, alpha: 0.28 * level),
                             shadowRadius: 34,
                             shadowOpacity: 0.9 * level,
                             shadowColor: RGBA(packed: tint)),
            bloom: LayerStyle(lineWidth: width * 1.35,
                              stroke: RGBA(packed: tint, alpha: 0.62 * level),
                              shadowRadius: 18,
                              shadowOpacity: 0.95 * level,
                              shadowColor: RGBA(packed: tint)),
            core: LayerStyle(lineWidth: width,
                             stroke: RGBA(packed: tint, alpha: 0.96 * level),
                             shadowRadius: 10,
                             shadowOpacity: 0.75 * level,
                             shadowColor: RGBA(packed: tint)),
            highlight: LayerStyle(lineWidth: max(1.5, width * 0.18),
                                  stroke: .white(alpha: 0.82 * level),
                                  shadowRadius: 4,
                                  shadowOpacity: 0.5 * level,
                                  shadowColor: .white(alpha: 1)))
    }
}

/// Where the overlay window sits and where the ring is stroked inside it.
public struct OverlayGeometry: Equatable, Sendable {
    public let windowFrame: CGRect
    public let pathRect: CGRect
    public let cornerRadius: CGFloat

    public init(windowFrame: CGRect, pathRect: CGRect, cornerRadius: CGFloat) {
        self.windowFrame = windowFrame
        self.pathRect = pathRect
        self.cornerRadius = cornerRadius
    }

    public var bounds: CGRect { CGRect(origin: .zero, size: windowFrame.size) }

    /// Core Animation clips layers at the window boundary, which would make
    /// the glow disappear exactly where it is most useful: along the display
    /// edge. Pad the window outwards whenever the bloom is drawn.
    public static let glowPadding: CGFloat = 64

    public static func make(frame: CGRect, width: CGFloat, radius: CGFloat, glowing: Bool) -> OverlayGeometry {
        let padding = glowing ? glowPadding : 0
        let windowFrame = frame.insetBy(dx: -padding, dy: -padding)
        let stroked = frame
            .offsetBy(dx: padding - frame.minX, dy: padding - frame.minY)
            .insetBy(dx: width / 2, dy: width / 2)
        return OverlayGeometry(windowFrame: windowFrame,
                               pathRect: stroked,
                               cornerRadius: max(0, radius))
    }
}
