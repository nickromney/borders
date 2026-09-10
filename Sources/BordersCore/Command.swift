import Foundation

/// A command accepted over the local Unix socket.
public enum Command: Equatable, Sendable {
    case setMode(Mode)
    case reload
    case status
    case quit

    /// Every spelling the client and the server agree on.
    public static let names = ["on", "focused", "ring", "ring-light", "off",
                               "reload", "reconcile", "status", "quit"]

    public static func parse(_ raw: String) -> Command? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "on", "focused": return .setMode(.focused)
        case "ring", "ring-light": return .setMode(.ringLight)
        case "off": return .setMode(.off)
        case "reload", "reconcile": return .reload
        case "status": return .status
        case "quit": return .quit
        default: return nil
        }
    }

    public static func isClientCommand(_ raw: String) -> Bool {
        parse(raw) != nil
    }
}
