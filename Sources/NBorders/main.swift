import AppKit
import CoreGraphics
import Foundation

private enum Mode: String { case off, focused, ringLight }
private enum DisplayChoice: String { case main, focused, all }

private struct Defaults {
    var color: UInt32 = 0xfff5f543
    var width: CGFloat = 5
    var gap: CGFloat = 0
    var radius: CGFloat = 10
    var ringAppBundleID: String?
}

private let socketPath = "/tmp/borders.sock"
private let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/borders/borders.conf")

private func readDefaults() -> Defaults {
    var result = Defaults()
    guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return result }
    for line in text.split(separator: "\n") {
        let item = line.trimmingCharacters(in: .whitespaces)
        guard !item.isEmpty, !item.hasPrefix("#"), let split = item.firstIndex(of: "=") else { continue }
        let key = item[..<split].trimmingCharacters(in: .whitespaces)
        let value = item[item.index(after: split)...].trimmingCharacters(in: .whitespaces)
        switch key {
        case "width": result.width = CGFloat(Double(value) ?? Double(result.width))
        case "gap": result.gap = CGFloat(Double(value) ?? Double(result.gap))
        case "radius": result.radius = CGFloat(Double(value) ?? Double(result.radius))
        case "color": result.color = UInt32(value.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? result.color
        case "ring_app", "ring-app": result.ringAppBundleID = value.isEmpty ? nil : value
        default: break
        }
    }
    return result
}

private func color(_ value: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: alpha * CGFloat((value >> 24) & 255) / 255)
}

private final class Overlay {
    let window: NSWindow
    private let glow = CAShapeLayer()
    private let bloom = CAShapeLayer()
    private let shape = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private let glowPadding: CGFloat = 64

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
        // Keep the bloom inside a padded window. Core Animation clips layers
        // at the window boundary, which otherwise makes the glow disappear
        // exactly where it is most useful: along the display edge.
        view.layer?.masksToBounds = false
        view.layer?.addSublayer(glow)
        view.layer?.addSublayer(bloom)
        view.layer?.addSublayer(shape)
        view.layer?.addSublayer(highlight)
        window.contentView = view
    }
    func hide() { window.orderOut(nil) }
    func draw(frame: CGRect, width: CGFloat, radius: CGFloat, tint: UInt32, brightness: CGFloat,
              glowing: Bool = true) {
        let padding = glowing ? glowPadding : 0
        let outer = frame.insetBy(dx: -padding, dy: -padding)
        if window.frame != outer { window.setFrame(outer, display: false) }
        let bounds = CGRect(origin: .zero, size: outer.size)
        let pathBounds = frame.offsetBy(dx: padding - frame.minX, dy: padding - frame.minY)
        let path = CGPath(roundedRect: pathBounds.insetBy(dx: width / 2, dy: width / 2),
                          cornerWidth: max(0, radius), cornerHeight: max(0, radius), transform: nil)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if glowing {
            configure(glow, bounds: bounds, path: path, lineWidth: width * 2.2,
                      stroke: color(tint, alpha: 0.28 * brightness),
                      shadowRadius: 34, shadowOpacity: 0.9 * brightness,
                      shadowColor: color(tint))
            configure(bloom, bounds: bounds, path: path, lineWidth: width * 1.35,
                      stroke: color(tint, alpha: 0.62 * brightness),
                      shadowRadius: 18, shadowOpacity: 0.95 * brightness,
                      shadowColor: color(tint))
            // The reference implementation uses a white gradient core. A
            // white core reads substantially brighter than a tinted stroke at
            // full opacity while the lower layers preserve the selected colour.
            configure(shape, bounds: bounds, path: path, lineWidth: width,
                      stroke: color(tint, alpha: min(1, 0.96 * brightness)),
                      shadowRadius: 10, shadowOpacity: 0.75 * brightness,
                      shadowColor: color(tint))
            configure(highlight, bounds: bounds, path: path, lineWidth: max(1.5, width * 0.18),
                      stroke: white(alpha: min(1, 0.82 * brightness)),
                      shadowRadius: 4, shadowOpacity: 0.5 * brightness,
                      shadowColor: white(alpha: 1))
        } else {
            // Focused-window mode stays a restrained solid border. The bloom
            // is a ring-light treatment and can also be disabled there when a
            // quiet display edge is preferred.
            configure(glow, bounds: bounds, path: path, lineWidth: 0,
                      stroke: white(alpha: 0), shadowRadius: 0, shadowOpacity: 0,
                      shadowColor: white(alpha: 0))
            configure(bloom, bounds: bounds, path: path, lineWidth: 0,
                      stroke: white(alpha: 0), shadowRadius: 0, shadowOpacity: 0,
                      shadowColor: white(alpha: 0))
            configure(shape, bounds: bounds, path: path, lineWidth: width,
                      stroke: color(tint, alpha: brightness),
                      shadowRadius: 0, shadowOpacity: 0, shadowColor: white(alpha: 0))
            configure(highlight, bounds: bounds, path: path, lineWidth: 0,
                      stroke: white(alpha: 0), shadowRadius: 0, shadowOpacity: 0,
                      shadowColor: white(alpha: 0))
        }
        CATransaction.commit()
        if !window.isVisible { window.orderFrontRegardless() }
    }

    private func configure(_ layer: CAShapeLayer, bounds: CGRect, path: CGPath, lineWidth: CGFloat,
                            stroke: CGColor, shadowRadius: CGFloat, shadowOpacity: CGFloat,
                            shadowColor: CGColor) {
        layer.frame = bounds
        layer.lineWidth = lineWidth
        layer.strokeColor = stroke
        layer.fillColor = nil
        layer.path = path
        layer.shadowColor = shadowColor
        layer.shadowOffset = .zero
        layer.shadowRadius = shadowRadius
        layer.shadowOpacity = Float(min(1, max(0, shadowOpacity)))
        // Do not provide the centerline as shadowPath. CAShapeLayer can treat
        // that rounded rectangle as a filled path, which turns the entire
        // focused window/display interior into a tinted panel. Leaving this
        // unset makes Core Animation derive the shadow from the stroked alpha
        // content instead.
        layer.shadowPath = nil
    }
}

private func white(alpha: CGFloat) -> CGColor {
    CGColor(gray: 1, alpha: min(1, max(0, alpha)))
}

private final class BorderEngine {
    private(set) var mode: Mode = Mode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "off") ?? .off
    private(set) var display = DisplayChoice(rawValue: UserDefaults.standard.string(forKey: "display") ?? "main") ?? .main
    private(set) var width = CGFloat(UserDefaults.standard.double(forKey: "width"))
    private(set) var brightness = CGFloat(UserDefaults.standard.double(forKey: "brightness"))
    private(set) var tint = UInt32(UserDefaults.standard.integer(forKey: "tint"))
    private(set) var neon = UserDefaults.standard.object(forKey: "neon") as? Bool ?? true
    private var defaults = readDefaults()
    private var overlays: [Overlay] = []
    private var timer: Timer?
    private var lastFocusedFrame = CGRect.zero
    private var lastFocusedPID: pid_t = 0
    private(set) var boundAppBundleID: String?
    private(set) var boundAppName: String?
    private var lastExternalAppBundleID: String?
    private var lastExternalAppName: String?
    private var lastExternalAppPID: pid_t = 0

    init() {
        if width == 0 { width = 24 }
        if brightness == 0 { brightness = 1 }
        if tint == 0 { tint = defaults.color }
        let storedBinding = UserDefaults.standard.object(forKey: "ringAppBundleID") as? String
        boundAppBundleID = storedBinding.map { $0.isEmpty ? nil : $0 } ?? defaults.ringAppBundleID
        boundAppName = UserDefaults.standard.string(forKey: "ringAppName")
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    func start() { timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.render() }; render() }
    func setMode(_ value: Mode) { mode = value; save("mode", value.rawValue); render() }
    func setDisplay(_ value: DisplayChoice) { display = value; save("display", value.rawValue); render() }
    func setWidth(_ value: CGFloat) { width = min(40, max(8, value)); save("width", width); render() }
    func setBrightness(_ value: CGFloat) { brightness = min(1, max(0, value)); save("brightness", brightness); render() }
    func setTint(_ value: UInt32) { tint = value; save("tint", Int(value)); render() }
    func setNeon(_ value: Bool) { neon = value; save("neon", value); render() }
    func reload() {
        defaults = readDefaults()
        if UserDefaults.standard.object(forKey: "ringAppBundleID") == nil {
            boundAppBundleID = defaults.ringAppBundleID
            boundAppName = nil
        }
        render()
    }
    func status() -> String {
        let app = boundAppBundleID ?? "any"
        return "mode=\(mode.rawValue) display=\(display.rawValue) width=\(Int(width)) brightness=\(Int(brightness * 100)) neon=\(neon ? "on" : "off") app=\(app)"
    }
    private func save(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: key) }

    var appBindingSummary: String {
        boundAppBundleID == nil ? "Any app" : (boundAppName ?? boundAppBundleID ?? "Any app")
    }

    var lastExternalAppSummary: String {
        lastExternalAppName ?? lastExternalAppBundleID ?? "last active app"
    }

    func bindToLastExternalApp() {
        guard let bundleID = lastExternalAppBundleID else { return }
        boundAppBundleID = bundleID
        boundAppName = lastExternalAppName
        save("ringAppBundleID", bundleID)
        save("ringAppName", lastExternalAppName ?? bundleID)
        render()
    }

    func clearAppBinding() {
        boundAppBundleID = nil
        boundAppName = nil
        // An empty preference is an intentional clear and prevents a config
        // baseline from silently re-binding the light on every reload.
        save("ringAppBundleID", "")
        UserDefaults.standard.removeObject(forKey: "ringAppName")
        render()
    }

    private func selectedScreens() -> [NSScreen] {
        switch display {
        case .all: return NSScreen.screens
        case .main: return NSScreen.main.map { [$0] } ?? []
        case .focused:
            guard let frame = focusedFrame()?.0 else { return NSScreen.main.map { [$0] } ?? [] }
            return NSScreen.screens.filter { $0.frame.intersects(frame) }
        }
    }
    private func render() {
        if mode == .ringLight { renderRingLight(); return }
        guard mode == .focused, let (frame, pid) = focusedFrame(), !isFullscreen(frame) else {
            overlays.forEach { $0.hide() }
            return
        }
        if overlays.isEmpty { overlays = [Overlay()] }
        for index in 1..<overlays.count { overlays[index].hide() }
        let pad = defaults.width + defaults.gap
        overlays[0].draw(frame: frame.insetBy(dx: -pad, dy: -pad), width: defaults.width,
                         radius: defaults.radius, tint: defaults.color, brightness: 1, glowing: false)
        lastFocusedFrame = frame; lastFocusedPID = pid
    }
    private func renderRingLight() {
        guard isBoundAppActive() else {
            overlays.forEach { $0.hide() }
            return
        }
        let screens = selectedScreens()
        while overlays.count < screens.count { overlays.append(Overlay()) }
        for (index, screen) in screens.enumerated() {
            // Safe-area insets are in screen coordinates; inset all edges so a
            // notched display never receives a stroke through its camera cutout.
            let safe = screen.visibleFrame
            overlays[index].draw(frame: safe, width: width, radius: 18, tint: tint,
                                 brightness: brightness, glowing: neon)
        }
        for index in screens.count..<overlays.count { overlays[index].hide() }
    }
    private func focusedFrame() -> (CGRect, pid_t)? {
        guard let pid = activeExternalAppPID() else { return nil }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let candidates = list.enumerated().compactMap { index, item -> WindowCandidate? in
            guard (item[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (item[kCGWindowLayer as String] as? Int) == 0,
                  (item[kCGWindowAlpha as String] as? CGFloat ?? 1) > 0,
                  let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat,
                  w > 60, h > 60 else { return nil }
            return WindowCandidate(order: index, frame: cocoaRect(CGRect(x: x, y: y, width: w, height: h)))
        }

        // CGWindowList is ordered front-to-back, so the first candidate is
        // normally the focused window. That is not what we want here: browser
        // pop-outs, find panels, and permission sheets can temporarily be first
        // even though the user's main window is the useful focus target. Pick
        // the largest visible layer-0 window and use front-to-back order only
        // to break ties.
        guard let primary = candidates.max(by: { lhs, rhs in
            if lhs.area == rhs.area { return lhs.order > rhs.order }
            return lhs.area < rhs.area
        }) else { return nil }
        return (primary.frame, pid)
    }

    private struct WindowCandidate {
        let order: Int
        let frame: CGRect
        var area: CGFloat { frame.width * frame.height }
    }

    private func activeExternalAppPID() -> pid_t? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           activePID != ownPID {
            return activePID
        }
        return lastExternalAppPID == 0 ? nil : lastExternalAppPID
    }

    private func cocoaRect(_ rect: CGRect) -> CGRect {
        // Quartz window bounds use a top-left origin; AppKit uses a
        // bottom-left origin. The reference line is the main display's global
        // top edge, not an arbitrary entry in NSScreen.screens (important when
        // a second display is positioned above or below the main one).
        let mainTop = NSScreen.main?.frame.maxY ?? NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: mainTop - rect.maxY, width: rect.width, height: rect.height)
    }
    private func isFullscreen(_ rect: CGRect) -> Bool { NSScreen.screens.contains { $0.frame.intersection(rect).height >= $0.frame.height - 8 && rect.minY <= $0.frame.minY + 8 } }

    private func isBoundAppActive() -> Bool {
        guard let boundAppBundleID else { return true }
        let active = NSWorkspace.shared.frontmostApplication
        if active?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return lastExternalAppBundleID == boundAppBundleID
        }
        return active?.bundleIdentifier == boundAppBundleID
    }

    private func rememberExternalApplication(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier else { return }
        lastExternalAppBundleID = bundleID
        lastExternalAppName = app.localizedName ?? bundleID
        lastExternalAppPID = app.processIdentifier
    }

    @objc private func applicationActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        rememberExternalApplication(app)
        render()
    }
    @objc private func screensChanged() { overlays.forEach { $0.hide() }; render() }
}

private final class MenuController: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let engine: BorderEngine
    let launchManager: LaunchAtLoginManager
    init(engine: BorderEngine) {
        self.engine = engine
        self.launchManager = LaunchAtLoginManager()
        super.init()
        build()
    }
    private func build() {
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "Borders")
        statusItem.button?.toolTip = "Borders"
        let menu = NSMenu(); menu.autoenablesItems = false
        menu.addItem(item("Focused window", #selector(focused), checked: engine.mode == .focused))
        menu.addItem(item("Ring light", #selector(ring), checked: engine.mode == .ringLight))
        menu.addItem(item("Off", #selector(off), checked: engine.mode == .off))
        menu.addItem(.separator())
        menu.addItem(item("Main display", #selector(mainDisplay), checked: engine.display == .main))
        menu.addItem(item("Focused display", #selector(focusedDisplay), checked: engine.display == .focused))
        menu.addItem(item("All displays", #selector(allDisplays), checked: engine.display == .all))
        if launchManager.canManageLaunchAtLogin {
            menu.addItem(.separator())
            menu.addItem(item("Open at Login", #selector(toggleLaunchAtLogin), checked: launchManager.isEnabled))
            if launchManager.requiresApproval {
                menu.addItem(item("Allow in Login Items…", #selector(openLoginItemsSettings)))
            }
        }
        menu.addItem(.separator())
        menu.addItem(item("Ring light app: \(engine.appBindingSummary)", nil))
        menu.addItem(item("Bind to \(engine.lastExternalAppSummary)", #selector(bindToCurrentApp)))
        menu.addItem(item("Clear app binding", #selector(clearAppBinding), checked: engine.boundAppBundleID == nil))
        menu.addItem(.separator())
        let width = NSMenuItem(title: "Width: \(Int(engine.width)) points", action: nil, keyEquivalent: ""); menu.addItem(width)
        menu.addItem(item("Neon bloom", #selector(toggleNeon), checked: engine.neon))
        for value in stride(from: 8, through: 40, by: 8) { menu.addItem(item("  \(value) points", #selector(setWidth(_:)), represented: value, checked: Int(engine.width) == value)) }
        menu.addItem(item("Brightness: \(Int(engine.brightness * 100))%", nil))
        for value in [0.25, 0.5, 0.75, 1.0] { menu.addItem(item("  \(Int(value * 100))%", #selector(setBrightness(_:)), represented: value, checked: abs(engine.brightness - value) < 0.01)) }
        menu.addItem(.separator())
        menu.addItem(item("Colour (ring light): Warm white", #selector(setTint(_:)), represented: UInt32(0xffffd6a3), checked: engine.tint == 0xffffd6a3))
        menu.addItem(item("Colour (ring light): Cool white", #selector(setTint(_:)), represented: UInt32(0xffd9ecff), checked: engine.tint == 0xffd9ecff))
        menu.addItem(item("Colour (ring light): Yellow", #selector(setTint(_:)), represented: UInt32(0xffffe45c), checked: engine.tint == 0xffffe45c))
        menu.addItem(item("Colour (ring light): Blue", #selector(setTint(_:)), represented: UInt32(0xff9cc7ff), checked: engine.tint == 0xff9cc7ff))
        menu.addItem(.separator()); menu.addItem(item("Reload configuration", #selector(reload))); menu.addItem(item("Open configuration", #selector(openConfig))); menu.addItem(item("Quit", #selector(quit)))
        statusItem.menu = menu
    }
    private func item(_ title: String, _ action: Selector?, represented: Any? = nil, checked: Bool = false) -> NSMenuItem { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; item.state = checked ? .on : .off; item.representedObject = represented; return item }
    @objc private func focused() { engine.setMode(.focused); build() }
    @objc private func ring() { engine.setMode(.ringLight); build() }
    @objc private func off() { engine.setMode(.off); build() }
    @objc private func mainDisplay() { engine.setDisplay(.main); build() }
    @objc private func focusedDisplay() { engine.setDisplay(.focused); build() }
    @objc private func allDisplays() { engine.setDisplay(.all); build() }
    @objc private func toggleLaunchAtLogin() {
        launchManager.setEnabled(!launchManager.isEnabled)
        build()
    }
    @objc private func openLoginItemsSettings() { launchManager.openLoginItemsSettings() }
    @objc private func bindToCurrentApp() { engine.bindToLastExternalApp(); build() }
    @objc private func clearAppBinding() { engine.clearAppBinding(); build() }
    @objc private func toggleNeon() { engine.setNeon(!engine.neon); build() }
    @objc private func setWidth(_ item: NSMenuItem) { if let value = item.representedObject as? Int { engine.setWidth(CGFloat(value)); build() } }
    @objc private func setBrightness(_ item: NSMenuItem) { if let value = item.representedObject as? Double { engine.setBrightness(CGFloat(value)); build() } }
    @objc private func setTint(_ item: NSMenuItem) { if let value = item.representedObject as? UInt32 { engine.setTint(value); build() } }
    @objc private func reload() { engine.reload(); build() }
    @objc private func openConfig() { NSWorkspace.shared.open(configURL) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

private final class SocketServer {
    let engine: BorderEngine
    init(engine: BorderEngine) { self.engine = engine }
    func start() {
        unlink(socketPath); let fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0 else { return }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX); withUnsafeMutableBytes(of: &address.sun_path) { path in socketPath.utf8CString.withUnsafeBytes { path.copyBytes(from: $0) } }
        withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }; Darwin.listen(fd, 4)
        DispatchQueue.global(qos: .utility).async { while true { let client = Darwin.accept(fd, nil, nil); if client >= 0 { self.handle(client) } } }
    }
    private func handle(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 512)
        let count = Darwin.read(fd, &buffer, buffer.count)
        let command = String(bytes: buffer.prefix(max(0, count)), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // The server accepts clients on a utility queue, but every engine command
        // can ultimately manipulate AppKit windows. Keep that work on the main
        // thread; AppKit deliberately traps when a window is ordered from here.
        let reply = DispatchQueue.main.sync { execute(command) }
        _ = reply.withCString { Darwin.write(fd, $0, strlen($0)) }
        Darwin.close(fd)
    }
    private func execute(_ command: String) -> String {
        switch command {
        case "on", "focused": engine.setMode(.focused)
        case "ring", "ring-light": engine.setMode(.ringLight)
        case "off": engine.setMode(.off)
        case "reload", "reconcile": engine.reload()
        case "status": break
        default: return "unknown command"
        }
        return engine.status()
    }
    private func unlink(_ path: String) { Darwin.unlink(path) }
}

private func runClient(_ command: String) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0 else { return 1 }; var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX); withUnsafeMutableBytes(of: &address.sun_path) { path in socketPath.utf8CString.withUnsafeBytes { path.copyBytes(from: $0) } }; let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }; guard connected == 0 else { fputs("borders: app is not running\n", stderr); return 1 }; _ = command.withCString { Darwin.write(fd, $0, strlen($0)) }; var buffer = [UInt8](repeating: 0, count: 512); let count = Darwin.read(fd, &buffer, buffer.count); print(String(bytes: buffer.prefix(max(0, count)), encoding: .utf8) ?? ""); Darwin.close(fd); return 0
}

let arguments = Array(CommandLine.arguments.dropFirst())
if let command = arguments.first, ["on", "off", "status", "reconcile", "ring", "ring-light"].contains(command) { exit(runClient(command)) }
let application = NSApplication.shared; application.setActivationPolicy(.accessory); private let engine = BorderEngine(); private let menuController = MenuController(engine: engine); private let socketServer = SocketServer(engine: engine); socketServer.start(); engine.start(); application.run()
