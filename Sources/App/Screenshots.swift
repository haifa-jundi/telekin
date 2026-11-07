import AppKit
import SwiftUI

/// `Telekin --render-screenshots DIR` draws each page with demo motion into PNGs (for the README).
/// It never touches the cursor, Bluetooth or permissions.
@MainActor
enum Screenshots {
    static let size = CGSize(width: 900, height: 940)

    static func render(into directory: URL) -> Int32 {
        let model = TelekinModel(controller: PointerController(store: SettingsStore(defaults: UserDefaults(suiteName: "telekin.screenshots") ?? .standard)))
        model.replay(demoMotion(), rate: 50, cursorSpeed: 412, clicks: 7, tilt: 17)
        model.statusChanged(.pointing)
        model.update { $0.scroll.tiltScroll = true }

        let pages: [(String, AnyView)] = [
            ("home", AnyView(HomeView(model: model))),
            ("motion", AnyView(MotionView(model: model))),
            ("clicks", AnyView(ClicksView(model: model))),
            ("scroll", AnyView(ScrollPage(model: model))),
            ("feel", AnyView(FeelView(model: model))),
            ("setup", AnyView(SetupView(model: model))),
        ]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, view) in pages {
                let renderer = ImageRenderer(content: view.spellControls().environment(\.staticRendering, true).frame(width: size.width, height: size.height).preferredColorScheme(.dark))
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                    print("FAIL: could not render \(name)")
                    return 1
                }
                try png.write(to: directory.appendingPathComponent("\(name).png"))
                print("Wrote \(name).png")
            }
            return 0
        } catch {
            print("FAIL: \(error.localizedDescription)")
            return 1
        }
    }

    /// Six seconds of a head drawing a lazy figure-eight, at 50 Hz.
    private static func demoMotion() -> [MotionSample] {
        (0..<300).map { index in
            let t = Double(index) / 50
            let yaw = 22 * sin(t * 1.1)
            let pitch = 11 * sin(t * 2.2)
            let roll = 4 * sin(t * 0.7)
            return MotionSample(yaw: yaw, pitch: pitch, roll: roll,
                                yawRate: 22 * 1.1 * cos(t * 1.1), pitchRate: 11 * 2.2 * cos(t * 2.2),
                                rollRate: 4 * 0.7 * cos(t * 0.7), time: t)
        }
    }
}
