import AppKit
import BordersCore
import CoreGraphics
import Foundation

let socketPath = "/tmp/borders.sock"
let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/borders/borders.conf")

private func readConfiguration() -> Configuration {
    guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return Configuration() }
    return ConfigurationParser.parse(text)
}

private func storedSettings() -> StoredSettings {
    let store = UserDefaults.standard
    return StoredSettings(mode: store.string(forKey: "mode"),
                          display: store.string(forKey: "display"),
                          width: store.double(forKey: "width"),
                          brightness: store.double(forKey: "brightness"),
                          tint: store.integer(forKey: "tint"),
                          neon: store.object(forKey: "neon") as? Bool)
}

final class BorderEngine {
    private(set) var settings: Settings
    private(set) var binding: AppBinding
    private var configuration: Configuration
    private var overlays: [Overlay] = []
    private var timer: Timer?
    private var lastExternalPID: pid_t = 0

    var mode: Mode { settings.mode }
    var display: DisplayChoice { settings.display }
    var width: CGFloat { settings.width }
    var brightness: CGFloat { settings.brightness }
    var tint: UInt32 { settings.tint }
    var neon: Bool { settings.neon }
    var boundAppBundleID: String? { binding.boundBundleID }
    var appBindingSummary: String { binding.summary }
    var lastExternalAppSummary: String { binding.lastExternalSummary }

    init() {
        configuration = readConfiguration()
        settings = SettingsResolver.resolve(stored: storedSettings(), configuration: configuration)
        let resolved = AppBinding.resolveBinding(
            storedBundleID: UserDefaults.standard.object(forKey: "ringAppBundleID") as? String,
            storedName: UserDefaults.standard.string(forKey: "ringAppName"),
            configuredBundleID: configuration.ringAppBundleID)
        binding = AppBinding(boundBundleID: resolved.bundleID, boundName: resolved.name)
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.render() }
        render()
    }

    func setMode(_ value: Mode) { settings.mode = value; save("mode", value.rawValue); render() }
    func setDisplay(_ value: DisplayChoice) { settings.display = value; save("display", value.rawValue); render() }
    func setWidth(_ value: CGFloat) { settings.setWidth(value); save("width", settings.width); render() }
    func setBrightness(_ value: CGFloat) { settings.setBrightness(value); save("brightness", settings.brightness); render() }
    func setTint(_ value: UInt32) { settings.tint = value; save("tint", Int(value)); render() }
    func setNeon(_ value: Bool) { settings.neon = value; save("neon", value); render() }

    func reload() {
        configuration = readConfiguration()
        if UserDefaults.standard.object(forKey: "ringAppBundleID") == nil {
            binding.boundBundleID = configuration.ringAppBundleID
            binding.boundName = nil
        }
        render()
    }

    func status() -> String { settings.statusLine(boundAppBundleID: binding.boundBundleID) }

    private func save(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: key) }

    func bindToLastExternalApp() {
        guard binding.bindToLastExternal() else { return }
        save("ringAppBundleID", binding.boundBundleID ?? "")
        save("ringAppName", binding.boundName ?? "")
        render()
    }

    func clearAppBinding() {
        binding.clear()
        // An empty preference is an intentional clear and prevents a config
        // baseline from silently re-binding the light on every reload.
        save("ringAppBundleID", "")
        UserDefaults.standard.removeObject(forKey: "ringAppName")
        render()
    }

    private func selectedScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        let indices = WindowSelection.screenIndices(
            for: settings.display,
            screens: screens.map(\.frame),
            mainIndex: NSScreen.main.flatMap { screens.firstIndex(of: $0) },
            focusedFrame: settings.display == .focused ? focusedFrame()?.0 : nil)
        return indices.map { screens[$0] }
    }

    private func render() {
        switch settings.mode {
        case .ringLight: renderRingLight()
        case .focused: renderFocusedWindow()
        case .off: hideAll()
        }
    }

    private func hideAll() { overlays.forEach { $0.hide() } }

    private func renderFocusedWindow() {
        guard let (frame, _) = focusedFrame(),
              !WindowSelection.isFullscreen(frame, screens: NSScreen.screens.map(\.frame)) else {
            hideAll()
            return
        }
        if overlays.isEmpty { overlays = [Overlay()] }
        hide(from: 1)
        let pad = configuration.width + configuration.gap
        overlays[0].draw(frame: frame.insetBy(dx: -pad, dy: -pad), width: configuration.width,
                         radius: configuration.radius, tint: configuration.color,
                         brightness: 1, glowing: false)
    }

    private func renderRingLight() {
        guard isBoundAppActive() else {
            hideAll()
            return
        }
        let screens = selectedScreens()
        while overlays.count < screens.count { overlays.append(Overlay()) }
        for (index, screen) in screens.enumerated() {
            overlays[index].draw(frame: screen.visibleFrame, width: settings.width, radius: 18,
                                 tint: settings.tint, brightness: settings.brightness,
                                 glowing: settings.neon)
        }
        hide(from: screens.count)
    }

    private func hide(from index: Int) {
        guard index < overlays.count else { return }
        overlays[index...].forEach { $0.hide() }
    }

    private func focusedFrame() -> (CGRect, pid_t)? {
        guard let pid = activeExternalAppPID(),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        let mainTop = NSScreen.main?.frame.maxY ?? NSScreen.screens.first?.frame.maxY ?? 0
        let candidates = list.enumerated().compactMap { index, item -> WindowCandidate? in
            guard let quartz = WindowSelection.quartzFrame(from: item, pid: pid) else { return nil }
            return WindowCandidate(order: index,
                                   frame: WindowSelection.cocoaRect(quartz, mainTop: mainTop))
        }
        guard let primary = WindowSelection.primary(among: candidates) else { return nil }
        return (primary.frame, pid)
    }

    private func activeExternalAppPID() -> pid_t? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier, activePID != ownPID {
            return activePID
        }
        return lastExternalPID == 0 ? nil : lastExternalPID
    }

    private func isBoundAppActive() -> Bool {
        let active = NSWorkspace.shared.frontmostApplication
        let isSelf = active?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        return binding.isActive(frontmostBundleID: active?.bundleIdentifier, frontmostIsSelf: isSelf)
    }

    private func rememberExternalApplication(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier else { return }
        binding.rememberExternal(bundleID: bundleID, name: app.localizedName)
        lastExternalPID = app.processIdentifier
    }

    @objc private func applicationActivated(_ notification: Notification) {
        rememberExternalApplication(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        render()
    }

    @objc private func screensChanged() { hideAll(); render() }
}
