import CoreGraphics
import Foundation

public enum Mode: String, CaseIterable, Sendable {
    case off, focused, ringLight
}

public enum DisplayChoice: String, CaseIterable, Sendable {
    case main, focused, all
}

/// The live, user-adjustable settings, independent of where they are stored.
public struct Settings: Equatable, Sendable {
    public static let widthRange: ClosedRange<CGFloat> = 8...40
    public static let brightnessRange: ClosedRange<CGFloat> = 0...1

    public var mode: Mode
    public var display: DisplayChoice
    public var width: CGFloat
    public var brightness: CGFloat
    public var tint: UInt32
    public var neon: Bool

    public init(mode: Mode = .off,
                display: DisplayChoice = .main,
                width: CGFloat = 24,
                brightness: CGFloat = 1,
                tint: UInt32 = 0xfff5_f543,
                neon: Bool = true) {
        self.mode = mode
        self.display = display
        self.width = width
        self.brightness = brightness
        self.tint = tint
        self.neon = neon
    }

    public static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        guard !value.isNaN else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    public mutating func setWidth(_ value: CGFloat) {
        width = Settings.clamp(value, to: Settings.widthRange)
    }

    public mutating func setBrightness(_ value: CGFloat) {
        brightness = Settings.clamp(value, to: Settings.brightnessRange)
    }

    /// The single line reported over the socket and by `borders status`.
    public func statusLine(boundAppBundleID: String?) -> String {
        let app = boundAppBundleID ?? "any"
        return "mode=\(mode.rawValue) display=\(display.rawValue) width=\(Int(width))"
            + " brightness=\(Int(brightness * 100)) neon=\(neon ? "on" : "off") app=\(app)"
    }
}

/// The values persisted in `UserDefaults`, before defaulting is applied.
public struct StoredSettings: Equatable, Sendable {
    public var mode: String?
    public var display: String?
    public var width: Double
    public var brightness: Double
    public var tint: Int
    public var neon: Bool?

    public init(mode: String? = nil,
                display: String? = nil,
                width: Double = 0,
                brightness: Double = 0,
                tint: Int = 0,
                neon: Bool? = nil) {
        self.mode = mode
        self.display = display
        self.width = width
        self.brightness = brightness
        self.tint = tint
        self.neon = neon
    }
}

public enum SettingsResolver {
    /// Combine stored preferences with the configuration baseline.
    ///
    /// `UserDefaults` reports an absent number as zero, so a zero here means
    /// "never set" and takes the built-in default rather than a zero-width
    /// border nobody can see.
    public static func resolve(stored: StoredSettings, configuration: Configuration) -> Settings {
        var settings = Settings()
        settings.mode = stored.mode.flatMap(Mode.init(rawValue:)) ?? .off
        settings.display = stored.display.flatMap(DisplayChoice.init(rawValue:)) ?? .main
        if stored.width != 0 { settings.setWidth(CGFloat(stored.width)) }
        if stored.brightness != 0 { settings.setBrightness(CGFloat(stored.brightness)) }
        settings.tint = stored.tint == 0 ? configuration.color : UInt32(truncatingIfNeeded: stored.tint)
        settings.neon = stored.neon ?? true
        return settings
    }
}
