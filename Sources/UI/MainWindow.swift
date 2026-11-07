import AppKit
import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case home = "Wand", motion = "Motion", clicks = "Clicks", scroll = "Scroll", feel = "Feel", setup = "Setup", about = "About"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "wand.and.stars"
        case .motion: return "waveform.path.ecg"
        case .clicks: return "cursorarrow.click.2"
        case .scroll: return "scroll"
        case .feel: return "slider.horizontal.3"
        case .setup: return "checklist"
        case .about: return "info.circle"
        }
    }
}

struct MainView: View {
    @ObservedObject var model: TelekinModel

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $model.section) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(190)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.statusColor(model.status)).frame(width: 8, height: 8)
                    Text(model.status == .pointing ? String(format: "%.0f Hz · casting", model.rateHz) : Theme.statusTitle(model.status))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        } detail: {
            switch model.section {
            case .home: HomeView(model: model)
            case .motion: MotionView(model: model)
            case .clicks: ClicksView(model: model)
            case .scroll: ScrollPage(model: model)
            case .feel: FeelView(model: model)
            case .setup: SetupView(model: model)
            case .about: AboutView()
            }
        }
        .spellControls()
        .preferredColorScheme(.dark)
        .frame(minWidth: 820, minHeight: 600)
    }
}

/// Owns the main window. The app lives in the menu bar; the Dock icon only shows while the window is open.
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: TelekinModel
    private var window: NSWindow?

    init(model: TelekinModel) {
        self.model = model
    }

    func show(section: Section = .home) {
        if window == nil {
            let hosting = NSHostingController(rootView: MainView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Telekin"
            window.setContentSize(NSSize(width: 980, height: 680))
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("TelekinMain")
            self.window = window
        }
        model.section = section
        model.windowVisible = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.windowVisible = false
        NSApp.setActivationPolicy(.accessory)
    }
}
