import Foundation

/// Which app the ring light is bound to, and which app is in front.
public struct AppBinding: Equatable, Sendable {
    public var boundBundleID: String?
    public var boundName: String?
    public var lastExternalBundleID: String?
    public var lastExternalName: String?

    public init(boundBundleID: String? = nil,
                boundName: String? = nil,
                lastExternalBundleID: String? = nil,
                lastExternalName: String? = nil) {
        self.boundBundleID = boundBundleID
        self.boundName = boundName
        self.lastExternalBundleID = lastExternalBundleID
        self.lastExternalName = lastExternalName
    }

    public var summary: String {
        guard boundBundleID != nil else { return "Any app" }
        return boundName ?? boundBundleID ?? "Any app"
    }

    public var lastExternalSummary: String {
        lastExternalName ?? lastExternalBundleID ?? "last active app"
    }

    /// Bind to the last app that was in front other than Borders itself.
    ///
    /// Returns false when nothing has been remembered yet, so the caller can
    /// skip persisting a binding that would never match.
    @discardableResult
    public mutating func bindToLastExternal() -> Bool {
        guard let bundleID = lastExternalBundleID else { return false }
        boundBundleID = bundleID
        boundName = lastExternalName ?? bundleID
        return true
    }

    public mutating func clear() {
        boundBundleID = nil
        boundName = nil
    }

    public mutating func rememberExternal(bundleID: String?, name: String?) {
        guard let bundleID else { return }
        lastExternalBundleID = bundleID
        lastExternalName = name ?? bundleID
    }

    /// Whether the light should be shown for the app currently in front.
    ///
    /// While Borders' own menu is in front the frontmost app is Borders, so
    /// fall back to the remembered app rather than dropping the light every
    /// time the menu is opened.
    public func isActive(frontmostBundleID: String?, frontmostIsSelf: Bool) -> Bool {
        guard let boundBundleID else { return true }
        if frontmostIsSelf { return lastExternalBundleID == boundBundleID }
        return frontmostBundleID == boundBundleID
    }

    /// Resolve the binding stored in preferences against the config baseline.
    ///
    /// An empty stored value is an intentional clear and must win over the
    /// baseline, otherwise a reload silently re-binds the light.
    public static func resolveBinding(storedBundleID: String?,
                                      storedName: String?,
                                      configuredBundleID: String?) -> (bundleID: String?, name: String?) {
        guard let storedBundleID else { return (configuredBundleID, nil) }
        guard !storedBundleID.isEmpty else { return (nil, nil) }
        return (storedBundleID, storedName)
    }
}
