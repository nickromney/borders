import CoreGraphics
import Foundation

/// The portable baseline read from `~/.config/borders/borders.conf`.
///
/// The file is never written by the UI, so parsing is one-way and every
/// unparsable value falls back to the value already held.
public struct Configuration: Equatable, Sendable {
    public var color: UInt32
    public var width: CGFloat
    public var gap: CGFloat
    public var radius: CGFloat
    public var ringAppBundleID: String?

    public init(color: UInt32 = 0xfff5_f543,
                width: CGFloat = 5,
                gap: CGFloat = 0,
                radius: CGFloat = 10,
                ringAppBundleID: String? = nil) {
        self.color = color
        self.width = width
        self.gap = gap
        self.radius = radius
        self.ringAppBundleID = ringAppBundleID
    }
}

/// One `key = value` pair from the configuration file.
public struct ConfigurationEntry: Equatable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public enum ConfigurationParser {
    /// Split configuration text into entries, dropping blank and comment lines.
    ///
    /// Kept separate from application so the line grammar can be tested without
    /// reasoning about which key each entry lands on.
    public static func entries(in text: String) -> [ConfigurationEntry] {
        text.split(separator: "\n").compactMap { line in
            let item = line.trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty, !item.hasPrefix("#"), let split = item.firstIndex(of: "=") else { return nil }
            let key = item[..<split].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            let value = item[item.index(after: split)...].trimmingCharacters(in: .whitespaces)
            return ConfigurationEntry(key: key, value: value)
        }
    }

    /// Apply one entry to a configuration, leaving it untouched for an unknown
    /// key or an unparsable value.
    public static func apply(_ entry: ConfigurationEntry, to configuration: inout Configuration) {
        switch entry.key {
        case "width": configuration.width = length(entry.value, or: configuration.width)
        case "gap": configuration.gap = length(entry.value, or: configuration.gap)
        case "radius": configuration.radius = length(entry.value, or: configuration.radius)
        case "color": configuration.color = colour(entry.value, or: configuration.color)
        case "ring_app", "ring-app": configuration.ringAppBundleID = entry.value.isEmpty ? nil : entry.value
        default: break
        }
    }

    public static func parse(_ text: String, base: Configuration = Configuration()) -> Configuration {
        var result = base
        for entry in entries(in: text) {
            apply(entry, to: &result)
        }
        return result
    }

    static func length(_ value: String, or fallback: CGFloat) -> CGFloat {
        guard let parsed = Double(value), parsed.isFinite else { return fallback }
        return CGFloat(parsed)
    }

    static func colour(_ value: String, or fallback: UInt32) -> UInt32 {
        let digits = value.hasPrefix("0x") || value.hasPrefix("0X") ? String(value.dropFirst(2)) : value
        return UInt32(digits, radix: 16) ?? fallback
    }
}
