import SwiftUI

/// Tilt to scroll and scroll mode, with a live tilt gauge.
struct ScrollPage: View {
    @ObservedObject var model: TelekinModel

    var body: some View {
        Page(title: "Scroll", subtitle: "Lean into the page.") {
            Card("Tilt to scroll") {
                Toggle("Tilt your head to scroll: right goes down, left goes up", isOn: model.binding(\.scroll.tiltScroll))
                TiltGauge(tilt: model.tilt, deadzone: model.snapshot.scroll.tiltDeadzoneDegrees,
                          active: model.snapshot.scroll.tiltScroll && model.status == .pointing && !model.scrollMode)
                    .frame(height: 200)
                    .accessibilityElement()
                    .accessibilityLabel("Tilt gauge")
                    .accessibilityValue(TiltGauge.spokenValue(tilt: model.tilt, deadzone: model.snapshot.scroll.tiltDeadzoneDegrees,
                                                              active: model.snapshot.scroll.tiltScroll && model.status == .pointing && !model.scrollMode))
                HStack {
                    Text("Your current posture is neutral. Lean further to scroll faster.")
                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Button("Center") { model.controller.recenterTilt() }.help("Make your current tilt the neutral posture")
                }
                ScrollSliderRow(title: "Lean before scrolling", value: model.binding(\.scroll.tiltDeadzoneDegrees),
                                range: SettingsStore.tiltDeadzoneRange, format: "%.0f°",
                                hint: "Raise it if you scroll by accident while reading.")
            }

            Card("Scroll mode") {
                HStack(alignment: .center, spacing: 14) {
                    KeyChip(keys: "⌃⌥S", label: model.scrollMode ? "On: nod and turn to scroll" : "Off")
                    Spacer()
                    Button(model.scrollMode ? "Back to pointing" : "Start scroll mode") { model.controller.toggleScrollMode() }
                        .disabled(model.status != .pointing)
                }
                Text("The cursor stays put. Nod down to scroll down and turn to scroll sideways: handy for long pages, maps and timelines.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }

            Card("Both") {
                ScrollSliderRow(title: "Scroll speed", value: model.binding(\.scroll.speed), range: SettingsStore.scrollSpeedRange,
                                format: "%.1f×", hint: "Applies to tilt and scroll mode.")
                Toggle("Reverse scroll direction", isOn: model.binding(\.scroll.reverse))
            }
        }
    }
}

private struct ScrollSliderRow: View {
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
    }
}

/// A half-dial: the needle is your head tilt; the dim band in the middle is the dead zone.
/// Past the band, the needle glows and arrows show which way the page will scroll.
struct TiltGauge: View {
    let tilt: Double
    let deadzone: Double
    let active: Bool

    private static let span = 45.0 // degrees shown on each side

    static func spokenValue(tilt: Double, deadzone: Double, active: Bool) -> String {
        let degrees = String(format: "%.0f degrees %@", abs(tilt), tilt >= 0 ? "right" : "left")
        guard active, abs(tilt) > deadzone else { return "Tilted \(degrees), not scrolling" }
        return "Tilted \(degrees), scrolling \(tilt > 0 ? "down" : "up")"
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height - 44)
            let radius = min(size.width / 2, size.height - 44) - 14

            func angle(_ degrees: Double) -> Angle { .degrees(-90 + degrees / Self.span * 90) }
            func arc(from: Double, to: Double) -> Path {
                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: angle(from), endAngle: angle(to), clockwise: false)
                return path
            }

            context.stroke(arc(from: -Self.span, to: Self.span), with: .color(.white.opacity(0.1)),
                           style: StrokeStyle(lineWidth: 16, lineCap: .round))
            context.stroke(arc(from: -deadzone, to: deadzone), with: .color(.white.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 16, lineCap: .butt))

            let clamped = tilt.clamped(to: -Self.span...Self.span)
            let scrolling = active && abs(tilt) > deadzone
            if scrolling {
                let from = tilt > 0 ? deadzone : -clamped
                let to = tilt > 0 ? clamped : -deadzone
                var glow = context
                glow.addFilter(.blur(radius: 6))
                glow.stroke(arc(from: from, to: to), with: .color(Theme.spellEnd), style: StrokeStyle(lineWidth: 16))
                context.stroke(arc(from: from, to: to), with: .linearGradient(Gradient(colors: [Theme.spellStart, Theme.spellEnd]),
                                                                               startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                               style: StrokeStyle(lineWidth: 16))
            }

            let needleAngle = angle(clamped).radians
            let tip = CGPoint(x: center.x + cos(needleAngle) * (radius + 4), y: center.y + sin(needleAngle) * (radius + 4))
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: tip)
            context.stroke(needle, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(.white))

            let label = scrolling ? (tilt > 0 ? "Scrolling down ↓" : "Scrolling up ↑") : String(format: "Tilt %+.0f°", tilt)
            context.draw(Text(label).font(.callout.weight(.semibold)).foregroundStyle(scrolling ? Theme.spellEnd : .white.opacity(0.7)),
                         at: CGPoint(x: center.x, y: center.y + 30))
            context.draw(Text("↑ up").font(.caption).foregroundStyle(.white.opacity(0.5)), at: CGPoint(x: center.x - radius, y: center.y + 4))
            context.draw(Text("down ↓").font(.caption).foregroundStyle(.white.opacity(0.5)), at: CGPoint(x: center.x + radius, y: center.y + 4))
        }
    }
}
