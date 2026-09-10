import Foundation

public enum LaunchEligibility {
    /// Whether an app at this path may register itself as a login item.
    ///
    /// Keep developer builds from registering a login item that points at a
    /// disposable `.build` bundle. The installed copy lives in an
    /// `Applications` directory, so only those are eligible.
    public static func canManageLaunchAtLogin(bundleURL: URL) -> Bool {
        bundleURL.pathComponents.contains("Applications")
    }
}
