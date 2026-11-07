import AppKit

// Telekin: move the Mac cursor by turning your head with AirPods.
// Inspired by MousePods by Matteo Gaudioso (starman-tech), https://github.com/starman-tech/mousepods.

if CommandLine.arguments.contains("--self-test") {
    exit(MappingSelfTest.run())
}
if let flag = CommandLine.arguments.firstIndex(of: "--render-screenshots"), CommandLine.arguments.count > flag + 1 {
    _ = NSApplication.shared
    let target = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
    exit(MainActor.assumeIsolated { Screenshots.render(into: target) })
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = PointerController()
    private let store = SettingsStore()
    private lazy var model = TelekinModel(controller: controller)
    private lazy var windows = MainWindowController(model: model)
    private var menuBar: MenuBar?
    private var trail: SpellTrailOverlay?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = model // Created before start() so it receives the first motion samples.
        let trail = SpellTrailOverlay()
        self.trail = trail
        menuBar = MenuBar(controller: controller) { [weak self] section in self?.windows.show(section: section) }

        controller.onStatusChange = { [weak self] status in
            self?.model.statusChanged(status)
            self?.menuBar?.refresh()
        }
        controller.onScrollModeChange = { [weak self] on in
            self?.model.scrollModeChanged(on)
            self?.menuBar?.refresh()
        }
        controller.onCursorMove = { [weak self, weak trail] position, step in
            trail?.isEnabled = self?.controller.effects.spellTrail ?? false
            trail?.cursorMoved(to: position)
            self?.model.cursorMoved(by: step)
        }
        controller.onClick = { [weak self, weak trail] position, kind in
            trail?.isEnabled = self?.controller.effects.spellTrail ?? false
            trail?.burst(at: position, double: kind == .double)
            self?.model.clicked(kind)
        }
        controller.start()
        trail.isEnabled = controller.effects.spellTrail
        model.statusChanged(controller.status)

        // First launch, or something to fix: open on Setup. Otherwise stay quietly in the menu bar.
        if !store.setupSeen || !controller.accessibilityTrusted {
            store.setupSeen = true
            windows.show(section: .setup)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
