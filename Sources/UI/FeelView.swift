import SwiftUI

/// How the cursor responds to your head.
struct FeelView: View {
    @ObservedObject var model: TelekinModel

    var body: some View {
        Page(title: "Feel", subtitle: "Tune how the cursor answers your head.") {
            Card("Response") {
                SliderRow(title: "Speed", value: model.binding(\.settings.speed), range: SettingsStore.speedRange,
                          format: "%.1f×", hint: "How far the cursor moves for each degree you turn.")
                SliderRow(title: "Steadiness", value: model.binding(\.settings.deadzoneDegreesPerSecond), range: SettingsStore.deadzoneRange,
                          format: "%.1f °/s", hint: "Head movement slower than this is ignored. Raise it if the cursor drifts.")
                SliderRow(title: "Acceleration", value: model.binding(\.settings.acceleration), range: SettingsStore.accelerationRange,
                          format: "%.2f", hint: "Quick turns travel further; slow turns stay precise.")
            }

            Card("Direction") {
                Toggle("Invert left and right", isOn: model.binding(\.settings.invertHorizontal))
                Toggle("Invert up and down", isOn: model.binding(\.settings.invertVertical))
            }

            Card("Magic") {
                Toggle("Spell trail: sparkles follow the cursor while you steer", isOn: model.binding(\.effects.spellTrail))
                Text("Clicks burst into light. The sparkles never block what you click.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }

            Card("Startup") {
                LoginItemToggle()
            }

            Button("Reset to defaults") {
                model.update { snapshot in
                    snapshot.settings = MouseSettings()
                    snapshot.effects = EffectOptions()
                }
            }
        }
    }
}

/// "Open at login". The system owns this setting, so the toggle re-reads it whenever it appears.
private struct LoginItemToggle: View {
    @State private var state = LoginItem.state
    @State private var problem: String?

    var body: some View {
        Toggle("Open Telekin when you log in", isOn: Binding(
            get: { state != .off },
            set: { on in
                problem = LoginItem.set(on)
                state = LoginItem.state
            }))
        Group {
            if let problem {
                Text(problem).foregroundStyle(.orange)
            } else if state == .needsApproval {
                HStack {
                    Text("macOS needs your OK in System Settings › General › Login Items.").foregroundStyle(.orange)
                    Spacer()
                    Button("Open Login Items") { LoginItem.openSystemSettings() }
                }
            } else {
                Text("Keep Telekin in your Applications folder: if you move it, turn this off and on again.")
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { state = LoginItem.state }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).foregroundStyle(.white)
                Spacer()
                Text(String(format: format, value)).foregroundStyle(.white.opacity(0.7)).monospacedDigit()
            }
            .accessibilityHidden(true) // The slider below speaks the title and value.
            SpellSlider(value: $value, range: range)
                .accessibilityLabel(title)
                .accessibilityValue(String(format: format, value))
                .accessibilityHint(hint)
            Text(hint).font(.caption).foregroundStyle(.white.opacity(0.5)).accessibilityHidden(true)
        }
        .padding(.bottom, 6)
    }
}
