import AppKit
import BordersCore
import CoreGraphics

private func cgColor(_ rgba: RGBA) -> CGColor {
    CGColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
}

/// A single click-through window holding the stacked ring layers.
final class Overlay {
    let window: NSWindow
    private let layers = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.sharingType = .none
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        layers.forEach { view.layer?.addSublayer($0) }
        window.contentView = view
    }

    func hide() { window.orderOut(nil) }

    func draw(frame: CGRect, width: CGFloat, radius: CGFloat, tint: UInt32, brightness: CGFloat,
              glowing: Bool = true) {
        let geometry = OverlayGeometry.make(frame: frame, width: width, radius: radius, glowing: glowing)
        let style = OverlayStyle.make(width: width, brightness: brightness, tint: tint, glowing: glowing)
        if window.frame != geometry.windowFrame { window.setFrame(geometry.windowFrame, display: false) }
        let path = CGPath(roundedRect: geometry.pathRect,
                          cornerWidth: geometry.cornerRadius,
                          cornerHeight: geometry.cornerRadius,
                          transform: nil)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, spec) in zip(layers, style.layers) {
            configure(layer, bounds: geometry.bounds, path: path, style: spec)
        }
        CATransaction.commit()
        if !window.isVisible { window.orderFrontRegardless() }
    }

    private func configure(_ layer: CAShapeLayer, bounds: CGRect, path: CGPath, style: LayerStyle) {
        layer.frame = bounds
        layer.lineWidth = style.lineWidth
        layer.strokeColor = cgColor(style.stroke)
        layer.fillColor = nil
        layer.path = path
        layer.shadowColor = cgColor(style.shadowColor)
        layer.shadowOffset = .zero
        layer.shadowRadius = style.shadowRadius
        layer.shadowOpacity = Float(RGBA.clamped(style.shadowOpacity))
        // Do not provide the centreline as shadowPath. CAShapeLayer can treat
        // that rounded rectangle as a filled path, which turns the entire
        // focused window/display interior into a tinted panel. Leaving this
        // unset makes Core Animation derive the shadow from the stroked alpha
        // content instead.
        layer.shadowPath = nil
    }
}
