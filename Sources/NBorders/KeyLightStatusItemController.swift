import AppKit
import BordersCore
import Combine
import SwiftUI

/// Owns the separate Key Lights menu-bar item. Borders keeps its existing
/// menu for display overlays; this popover is deliberately focused on the
/// physical lights and mirrors the emergency-control affordance used by
/// AudioPriorityBar.
final class KeyLightStatusItemController: NSObject, ObservableObject, NSPopoverDelegate {
    private let engine: BorderEngine
    let store: KeyLightStore
    let brightnessFeedback: KeyLightBrightnessFeedbackController
    var keyLightsStateAction: ((Bool) -> Void)?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var observation: AnyCancellable?
    private var modeBeforeLightsOff: Mode?
    @Published private(set) var areAllLightsOff = false
    private weak var highlightedButton: NSStatusBarButton?

    init(engine: BorderEngine) {
        self.engine = engine
        store = KeyLightStore()
        brightnessFeedback = KeyLightBrightnessFeedbackController(store: store)
        super.init()

        statusItem.autosaveName = "Borders.studioLights"
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: KeyLightPanel(controller: self)
        )
        observation = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
    }

    func install() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItem(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.identifier = NSUserInterfaceItemIdentifier("Borders.studioLights")
        button.setAccessibilityIdentifier("Borders.studioLights")
        button.setAccessibilityLabel("Key Lights")
        button.toolTip = "Key Lights"
        button.imagePosition = .imageOnly
        updateStatusItem()
        store.start()
    }

    @objc private func handleStatusItem(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopoverFromBordersMenu(anchor: NSStatusBarButton?) {
        // Let menu tracking finish before positioning the popover. This keeps
        // the anchor window valid when Key Lights was opened from Borders.
        DispatchQueue.main.async { [weak self] in
            self?.showPopover(anchor: anchor)
        }
    }

    private func showPopover(anchor: NSStatusBarButton? = nil) {
        guard !popover.isShown, let button = anchor ?? statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        highlightedButton?.highlight(false)
        button.highlight(true)
        highlightedButton = button
    }

    func popoverDidClose(_ notification: Notification) {
        highlightedButton?.highlight(false)
        highlightedButton = nil
    }

    private func showContextMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Open Key Lights", #selector(openKeyLights)))
        menu.addItem(item("Refresh Key Lights", #selector(refresh)))
        menu.addItem(.separator())
        menu.addItem(item("Open Wi-Fi Settings…", #selector(openWiFiSettings)))
        menu.addItem(item("Open Pairing Page…", #selector(openPairingPage)))
        menu.addItem(.separator())
        menu.addItem(item(areAllLightsOff ? "Lights On" : "Lights Off", #selector(toggleAllLights)))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: "")
        result.target = self
        return result
    }

    @objc private func openKeyLights() { showPopover() }
    @objc private func refresh() { store.refresh() }
    @objc private func openWiFiSettings() { store.openWiFiSettings() }
    @objc private func openPairingPage() { store.openPairingPage() }

    func turnOnAllAtMinimum() {
        store.turnOnAll(
            at: KeyLightLimits.minimumVisibleBrightness,
            temperature: KeyLightLimits.temperature.lowerBound
        )
        updateStatusItem()
    }

    func turnOffAll() {
        store.turnOffAll()
        updateStatusItem()
    }

    @objc func toggleAllLights() {
        if areAllLightsOff {
            store.turnOnAll(
                at: KeyLightLimits.minimumVisibleBrightness,
                temperature: KeyLightLimits.temperature.lowerBound
            )
            if let mode = modeBeforeLightsOff {
                engine.setMode(mode)
            }
            modeBeforeLightsOff = nil
            areAllLightsOff = false
        } else {
            modeBeforeLightsOff = engine.mode == .off ? nil : engine.mode
            store.turnOffAll()
            engine.setMode(.off)
            areAllLightsOff = true
        }
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let knownStates = store.devices.compactMap { store.state(for: $0) }
        let allLightsAreKnownAndOff = !store.devices.isEmpty &&
            knownStates.count == store.devices.count &&
            knownStates.allSatisfy { !$0.isOn }
        areAllLightsOff = allLightsAreKnownAndOff
        keyLightsStateAction?(allLightsAreKnownAndOff)

        let anyLightOn = knownStates.contains { $0.isOn }
        let symbol = anyLightOn ? "lightbulb.2.fill" : "lightbulb.2"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Key Lights")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Key Lights — \(store.statusMessage)"
        button.setAccessibilityValue(store.statusMessage)
    }
}
