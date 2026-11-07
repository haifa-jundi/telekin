import AppKit
import Carbon

/// The menu bar icon, its quick menu, and the global shortcuts.
final class MenuBar: NSObject, NSMenuDelegate {
    private let controller: PointerController
    private let openWindow: (Section) -> Void
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var hotKeys: HotKeys?

    init(controller: PointerController, openWindow: @escaping (Section) -> Void) {
        self.controller = controller
        self.openWindow = openWindow
        super.init()
        menu.delegate = self
        item.menu = menu
        let symbol = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Telekin")
        symbol?.isTemplate = true
        item.button?.image = symbol
        if symbol == nil { item.button?.title = "TK" }
        let controlOption = UInt32(controlKey | optionKey)
        hotKeys = HotKeys([
            .init(keyCode: UInt32(kVK_ANSI_P), modifiers: controlOption) { [weak controller] in controller?.togglePause() },
            .init(keyCode: UInt32(kVK_ANSI_K), modifiers: controlOption) { [weak controller] in controller?.click(.single) },
            .init(keyCode: UInt32(kVK_ANSI_D), modifiers: controlOption) { [weak controller] in controller?.click(.double) },
        ])
        refresh()
    }

    func refresh() {
        item.button?.appearsDisabled = controller.status != .pointing
        item.button?.toolTip = "Telekin: " + Theme.statusTitle(controller.status)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: Theme.statusTitle(controller.status) + " · " + Theme.statusDetail(controller.status), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(action("Open Telekin…", #selector(openMain), key: "o"))
        menu.addItem(action(controller.paused ? "Resume  (⌃⌥P)" : "Pause  (⌃⌥P)", #selector(togglePause)))
        menu.addItem(.separator())
        menu.addItem(toggle("Click by holding still", controller.clicks.dwell, #selector(toggleDwell)))
        menu.addItem(toggle("Click with AirPods press", controller.clicks.stemPress, #selector(toggleStemPress)))
        menu.addItem(toggle("Spell trail", controller.effects.spellTrail, #selector(toggleTrail)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Telekin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.target = self
        return entry
    }

    private func toggle(_ title: String, _ on: Bool, _ selector: Selector) -> NSMenuItem {
        let entry = action(title, selector)
        entry.state = on ? .on : .off
        return entry
    }

    @objc private func openMain() { openWindow(.home) }
    @objc private func togglePause() { controller.togglePause() }
    @objc private func toggleDwell() { controller.update { $0.clicks.dwell.toggle() } }
    @objc private func toggleStemPress() { controller.update { $0.clicks.stemPress.toggle() } }
    @objc private func toggleTrail() { controller.update { $0.effects.spellTrail.toggle() } }
}
