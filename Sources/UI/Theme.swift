import SwiftUI

/// Telekin's look: a night sky with violet-to-cyan "spell" light.
enum Theme {
    static let spellStart = Color(red: 0.62, green: 0.38, blue: 1.0)
    static let spellEnd = Color(red: 0.25, green: 0.85, blue: 1.0)
    static let spark = Color(red: 1.0, green: 0.86, blue: 0.45)
    static let turn = Color(red: 0.36, green: 0.62, blue: 1.0)
    static let nod = Color(red: 0.36, green: 0.86, blue: 0.55)
    static let tilt = Color(red: 1.0, green: 0.64, blue: 0.28)

    static let spell = LinearGradient(colors: [spellStart, spellEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let sky = LinearGradient(colors: [Color(red: 0.05, green: 0.04, blue: 0.13), Color(red: 0.09, green: 0.06, blue: 0.22)],
                                    startPoint: .top, endPoint: .bottom)

    static func statusColor(_ status: PointerController.Status) -> Color {
        switch status {
        case .pointing: return spellEnd
        case .paused: return .orange
        case .waitingForHeadphones, .needsAccessibility: return .yellow
        case .failed: return .red
        }
    }

    static func statusTitle(_ status: PointerController.Status) -> String {
        switch status {
        case .pointing: return "Casting"
        case .paused: return "Paused"
        case .waitingForHeadphones: return "Waiting for AirPods"
        case .needsAccessibility: return "Needs Accessibility"
        case .failed: return "Something's off"
        }
    }

    static func statusDetail(_ status: PointerController.Status) -> String {
        switch status {
        case .pointing: return "Turn your head. The cursor follows."
        case .paused: return "Press ⌃⌥P or the button to resume."
        case .waitingForHeadphones: return "Wear your AirPods and pick them as sound output."
        case .needsAccessibility: return "Allow Telekin to move the cursor in Setup."
        case .failed(let message): return message
        }
    }
}

/// A rounded card on the dark sky.
struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.headline).foregroundStyle(.white.opacity(0.9))
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

/// A page with a title, a subtitle and the sky behind it.
struct Page<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    @Environment(\.staticRendering) private var staticRendering

    var body: some View {
        Group {
            // Image rendering can't draw inside a ScrollView, so screenshots lay the page out flat.
            if staticRendering { stack.frame(maxHeight: .infinity, alignment: .top) } else { ScrollView { stack } }
        }
        .background(Theme.sky.ignoresSafeArea())
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(subtitle).foregroundStyle(.white.opacity(0.6))
            }
            content
        }
        .padding(28)
        .frame(maxWidth: 860, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small keyboard-shortcut chip.
struct KeyChip: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Text(keys).font(.system(.body, design: .rounded).weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.12)))
            Text(label).foregroundStyle(.white.opacity(0.75))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Self.spoken(keys))")
    }

    /// "⌃⌥P" read aloud as "Control Option P".
    static func spoken(_ keys: String) -> String {
        let names: [Character: String] = ["⌃": "Control", "⌥": "Option", "⇧": "Shift", "⌘": "Command"]
        return keys.map { names[$0] ?? String($0) }.joined(separator: " ")
    }
}

/// A status dot with a soft glow.
struct StatusPill: View {
    let status: PointerController.Status

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.statusColor(status)).frame(width: 9, height: 9)
                .shadow(color: Theme.statusColor(status), radius: 6)
            Text(Theme.statusTitle(status)).font(.callout.weight(.semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.08)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(Theme.statusTitle(status))")
    }
}

private struct StaticRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while rendering README screenshots.
    var staticRendering: Bool {
        get { self[StaticRenderingKey.self] }
        set { self[StaticRenderingKey.self] = newValue }
    }
}

/// A glowing on/off switch in Telekin's colors.
struct SpellToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 12) {
                configuration.label.foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.35))
                Spacer(minLength: 12)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? AnyShapeStyle(Theme.spell) : AnyShapeStyle(Color.white.opacity(0.14)))
                        .frame(width: 40, height: 23)
                        .shadow(color: configuration.isOn ? Theme.spellStart.opacity(0.6) : .clear, radius: 6)
                    Circle().fill(.white).frame(width: 19, height: 19).padding(2)
                }
                .opacity(isEnabled ? 1 : 0.4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // VoiceOver and Voice Control see a standard switch, not a plain button.
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A soft capsule button.
struct SpellButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.22 : 0.12)))
            .overlay(Capsule().strokeBorder(Theme.spell.opacity(0.45)))
    }
}

/// A slider with a gradient track and a glowing knob.
struct SpellSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let knob: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - knob, 1)
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12)).frame(height: 6)
                Capsule().fill(Theme.spell).frame(width: knob / 2 + width * fraction, height: 6)
                Circle().fill(.white).frame(width: knob, height: knob)
                    .shadow(color: Theme.spellEnd.opacity(0.8), radius: 6)
                    .offset(x: width * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let position = ((drag.location.x - knob / 2) / width).clamped(to: 0...1)
                value = range.lowerBound + position * (range.upperBound - range.lowerBound)
            })
        }
        .frame(height: 24)
        .accessibilityRepresentation { Slider(value: $value, in: range) }
    }
}

extension View {
    /// Telekin's custom controls for everything inside.
    func spellControls() -> some View {
        toggleStyle(SpellToggleStyle()).buttonStyle(SpellButtonStyle())
    }
}
