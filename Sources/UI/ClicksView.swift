import SwiftUI

/// Ways to click, plus a practice target that hops around when you hit it.
struct ClicksView: View {
    @ObservedObject var model: TelekinModel

    var body: some View {
        Page(title: "Clicks", subtitle: "Cast a click without touching anything.") {
            Card("Hold still") {
                Toggle("Click by holding still for 1 second", isOn: model.binding(\.clicks.dwell))
                Toggle("Keep holding to 2 seconds to double-click", isOn: model.binding(\.clicks.dwellDoubleClick))
                    .disabled(!model.snapshot.clicks.dwell)
                Text("Move to a target, then hold your head still. Only head-driven movement arms it: using your mouse or trackpad never triggers a click, and resting on a page while reading won't keep clicking.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }

            Card("AirPods press · experimental") {
                Toggle("Press once to click, twice to double-click", isOn: model.binding(\.clicks.stemPress))
                Text("While Telekin is casting, a press clicks instead of pausing your music. Pause Telekin (⌃⌥P) and presses control music again. If another app starts playing, it may take the presses back.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }

            Card("Keyboard") {
                HStack(spacing: 24) {
                    KeyChip(keys: "⌃⌥K", label: "Click")
                    KeyChip(keys: "⌃⌥D", label: "Double-click")
                    KeyChip(keys: "⌃⌥P", label: "Pause")
                }
            }

            Card("Practice") {
                PracticeTarget()
                    .frame(height: 230)
            }
        }
    }
}

/// A glowing orb: click it (by any method) and it jumps somewhere else.
private struct PracticeTarget: View {
    @State private var position = CGPoint(x: 0.5, y: 0.5)
    @State private var hits = 0
    @State private var pulse = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.25))
                Text(hits == 0 ? "Steer onto the orb and click it" : "\(hits) hit\(hits == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12)
                Button {
                    hits += 1
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                        position = CGPoint(x: .random(in: 0.12...0.88), y: .random(in: 0.2...0.85))
                    }
                } label: {
                    Circle().fill(Theme.spell)
                        .frame(width: 54, height: 54)
                        .shadow(color: Theme.spellEnd, radius: pulse ? 22 : 10)
                        .overlay(Image(systemName: "sparkles").foregroundStyle(.white))
                }
                .buttonStyle(.plain)
                .position(x: position.x * geometry.size.width, y: position.y * geometry.size.height)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever()) { pulse = true } }
    }
}
