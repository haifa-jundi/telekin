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

            Button("Reset to defaults") {
                model.update { snapshot in
                    snapshot.settings = MouseSettings()
                    snapshot.effects = EffectOptions()
                }
            }
        }
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
            SpellSlider(value: $value, range: range)
            Text(hint).font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.bottom, 6)
    }
}
