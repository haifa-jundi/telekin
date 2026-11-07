import AppKit
import SwiftUI

/// First-run checklist: three permissions/conditions, each with a button that fixes it.
struct SetupView: View {
    @ObservedObject var model: TelekinModel
    /// Re-checked every second so the ticks turn green as soon as the user fixes something.
    @State private var tick = 0
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let _ = tick // Re-read the checks every second without resetting the page.
        Page(title: "Setup", subtitle: "Three steps, about a minute.") {
            Step(number: 1, done: model.motionAuthorized, title: "Let Telekin read head motion",
                 detail: "Allow Telekin under Privacy & Security › Motion & Fitness. The prompt appears the first time your AirPods connect.",
                 action: ("Open Motion & Fitness", { Self.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Motion") }))
            Step(number: 2, done: model.accessibilityTrusted, title: "Let Telekin move the cursor",
                 detail: "Turn Telekin on under Privacy & Security › Accessibility. After you rebuild the app, remove it from the list and add it again.",
                 action: ("Allow Accessibility", { model.controller.requestAccessibility() }))
            Step(number: 3, done: model.airPodsStreaming, title: "Wear your AirPods",
                 detail: "Put both in your ears and choose them as the sound output in Control Center › Sound. Head tracking only runs while they play audio.",
                 action: ("Try again", { model.controller.restartMotion() }))

            Card {
                HStack(spacing: 12) {
                    Image(systemName: model.isReady ? "wand.and.stars" : "hourglass")
                        .font(.title).foregroundStyle(model.isReady ? AnyShapeStyle(Theme.spell) : AnyShapeStyle(Color.white.opacity(0.5)))
                    VStack(alignment: .leading) {
                        Text(model.isReady ? "You're ready. Turn your head!" : "Finish the steps above")
                            .font(.headline).foregroundStyle(.white)
                        Text("Telekin works with AirPods (3rd gen), AirPods Pro, AirPods 4 and AirPods Max on macOS 15 or later.")
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
        }
        .onReceive(refresh) { _ in tick &+= 1 }
    }

    static func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct Step: View {
    let number: Int
    let done: Bool
    let title: String
    let detail: String
    let action: (String, () -> Void)

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().fill(done ? AnyShapeStyle(Theme.spell) : AnyShapeStyle(Color.white.opacity(0.1))).frame(width: 34, height: 34)
                    if done { Image(systemName: "checkmark").font(.headline).foregroundStyle(.white) }
                    else { Text("\(number)").font(.headline).foregroundStyle(.white) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(detail).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
                    if !done { Button(action.0, action: action.1).padding(.top, 4) }
                }
                Spacer()
            }
        }
    }
}
