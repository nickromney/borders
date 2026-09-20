import AppKit
import BordersCore

/// The tint choices offered in the menu, in order.
enum TintChoice: CaseIterable {
    case warmWhite, coolWhite, yellow, blue

    var title: String {
        switch self {
        case .warmWhite: return "Warm white"
        case .coolWhite: return "Cool white"
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        }
    }

    var value: UInt32 {
        switch self {
        case .warmWhite: return 0xffff_d6a3
        case .coolWhite: return 0xffd9_ecff
        case .yellow: return 0xffff_e45c
        case .blue: return 0xff9c_c7ff
        }
    }
}

final class MenuController: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let engine: BorderEngine
    let launchManager: LaunchAtLoginManager
    var keyLightsAction: ((NSStatusBarButton?) -> Void)?
    var keyLightsOnAction: (() -> Void)?
    var keyLightsOffAction: (() -> Void)?
    private var keyLightsAreOff = false
    private var keyLightsOffItem: NSMenuItem?

    private static let widths = Array(stride(from: 8, through: 40, by: 8))
    private static let brightnessLevels = [0.25, 0.5, 0.75, 1.0]

    init(engine: BorderEngine) {
        self.engine = engine
        self.launchManager = LaunchAtLoginManager()
        super.init()
        build()
    }

    private func build() {
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.dashed",
                                           accessibilityDescription: "Borders")
        statusItem.button?.toolTip = "Borders"
        let menu = NSMenu()
        menu.autoenablesItems = false
        addKeyLightItems(to: menu)
        addModeItems(to: menu)
        addDisplayItems(to: menu)
        addLaunchItems(to: menu)
        addBindingItems(to: menu)
        addAppearanceItems(to: menu)
        addTintItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(item("Reload configuration", #selector(reload)))
        menu.addItem(item("Open configuration", #selector(openConfig)))
        menu.addItem(item("Quit", #selector(quit)))
        statusItem.menu = menu
    }

    private func addKeyLightItems(to menu: NSMenu) {
        menu.addItem(item("Key Lights On (comes on at 5% warm)", #selector(turnOnKeyLights)))
        let offItem = item("Key Lights Off", #selector(turnOffKeyLights), checked: keyLightsAreOff)
        menu.addItem(offItem)
        keyLightsOffItem = offItem
        menu.addItem(item("Key Lights options…", #selector(openKeyLights)))
        menu.addItem(.separator())
    }

    func setKeyLightsAreOff(_ areOff: Bool) {
        keyLightsAreOff = areOff
        keyLightsOffItem?.state = areOff ? .on : .off
    }

    private func addModeItems(to menu: NSMenu) {
        menu.addItem(item("Focused window", #selector(focused), checked: engine.mode == .focused))
        menu.addItem(item("Ring light", #selector(ring), checked: engine.mode == .ringLight))
        menu.addItem(item("Off", #selector(off), checked: engine.mode == .off))
    }

    private func addDisplayItems(to menu: NSMenu) {
        menu.addItem(.separator())
        menu.addItem(item("Main display", #selector(mainDisplay), checked: engine.display == .main))
        menu.addItem(item("Focused display", #selector(focusedDisplay), checked: engine.display == .focused))
        menu.addItem(item("All displays", #selector(allDisplays), checked: engine.display == .all))
    }

    private func addLaunchItems(to menu: NSMenu) {
        guard launchManager.canManageLaunchAtLogin else { return }
        menu.addItem(.separator())
        menu.addItem(item("Open at Login", #selector(toggleLaunchAtLogin), checked: launchManager.isEnabled))
        guard launchManager.requiresApproval else { return }
        menu.addItem(item("Allow in Login Items…", #selector(openLoginItemsSettings)))
    }

    private func addBindingItems(to menu: NSMenu) {
        menu.addItem(.separator())
        menu.addItem(item("Ring light app: \(engine.appBindingSummary)", nil))
        menu.addItem(item("Bind to \(engine.lastExternalAppSummary)", #selector(bindToCurrentApp)))
        menu.addItem(item("Clear app binding", #selector(clearAppBinding),
                          checked: engine.boundAppBundleID == nil))
    }

    private func addAppearanceItems(to menu: NSMenu) {
        menu.addItem(.separator())
        menu.addItem(item("Width: \(Int(engine.width)) points", nil))
        menu.addItem(item("Neon bloom", #selector(toggleNeon), checked: engine.neon))
        for value in Self.widths {
            menu.addItem(item("  \(value) points", #selector(setWidth(_:)), represented: value,
                              checked: Int(engine.width) == value))
        }
        menu.addItem(item("Brightness: \(Int(engine.brightness * 100))%", nil))
        for value in Self.brightnessLevels {
            menu.addItem(item("  \(Int(value * 100))%", #selector(setBrightness(_:)), represented: value,
                              checked: abs(engine.brightness - CGFloat(value)) < 0.01))
        }
    }

    private func addTintItems(to menu: NSMenu) {
        menu.addItem(.separator())
        for choice in TintChoice.allCases {
            menu.addItem(item("Colour (ring light): \(choice.title)", #selector(setTint(_:)),
                              represented: choice.value, checked: engine.tint == choice.value))
        }
    }

    private func item(_ title: String, _ action: Selector?, represented: Any? = nil,
                      checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = checked ? .on : .off
        item.representedObject = represented
        return item
    }

    @objc private func focused() { engine.setMode(.focused); build() }
    @objc private func ring() { engine.setMode(.ringLight); build() }
    @objc private func off() { engine.setMode(.off); build() }
    @objc private func mainDisplay() { engine.setDisplay(.main); build() }
    @objc private func focusedDisplay() { engine.setDisplay(.focused); build() }
    @objc private func allDisplays() { engine.setDisplay(.all); build() }
    @objc private func turnOnKeyLights() { keyLightsOnAction?() }
    @objc private func turnOffKeyLights() { keyLightsOffAction?() }
    @objc private func toggleLaunchAtLogin() { launchManager.setEnabled(!launchManager.isEnabled); build() }
    @objc private func openLoginItemsSettings() { launchManager.openLoginItemsSettings() }
    @objc private func bindToCurrentApp() { engine.bindToLastExternalApp(); build() }
    @objc private func clearAppBinding() { engine.clearAppBinding(); build() }
    @objc private func toggleNeon() { engine.setNeon(!engine.neon); build() }
    @objc private func setWidth(_ item: NSMenuItem) {
        guard let value = item.representedObject as? Int else { return }
        engine.setWidth(CGFloat(value))
        build()
    }
    @objc private func setBrightness(_ item: NSMenuItem) {
        guard let value = item.representedObject as? Double else { return }
        engine.setBrightness(CGFloat(value))
        build()
    }
    @objc private func setTint(_ item: NSMenuItem) {
        guard let value = item.representedObject as? UInt32 else { return }
        engine.setTint(value)
        build()
    }
    @objc private func openKeyLights() { keyLightsAction?(statusItem.button) }
    @objc private func reload() { engine.reload(); build() }
    @objc private func openConfig() { NSWorkspace.shared.open(configURL) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
