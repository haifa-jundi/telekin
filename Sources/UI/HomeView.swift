import SwiftUI

/// The first page: a live "wand" you steer with your head, plus the big Cast/Pause button.
struct HomeView: View {
    @ObservedObject var model: TelekinModel

    var body: some View {
        Page(title: "Telekin", subtitle: "Move your Mac with a turn of your head.") {
            WandStage(model: model)
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.spell.opacity(0.35)))

            HStack(spacing: 14) {
                Card {
                    HStack(spacing: 8) {
                        StatusPill(status: model.status)
                        if model.scrollMode {
                            Text("Scroll mode · ⌃⌥S").font(.callout.weight(.semibold)).foregroundStyle(Theme.spellEnd)
                                .padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(Theme.spellEnd.opacity(0.15)))
                        }
                    }
                    Text(model.scrollMode ? "Nod or turn to scroll. The cursor stays put." : Theme.statusDetail(model.status)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                }
                CastButton(model: model).frame(width: 220)
            }

            HStack(spacing: 14) {
                Stat(value: model.rateHz, unit: "Hz", label: "Motion updates")
                Stat(value: model.cursorSpeed, unit: "px/s", label: "Cursor speed")
                Stat(value: Double(model.clickCount), unit: "", label: "Spells cast (clicks)")
            }

            Card("Shortcuts") {
                HStack(spacing: 24) {
                    KeyChip(keys: "⌃⌥P", label: "Pause")
                    KeyChip(keys: "⌃⌥K", label: "Click")
                    KeyChip(keys: "⌃⌥D", label: "Double-click")
                    KeyChip(keys: "⌃⌥S", label: "Scroll mode")
                }
            }
        }
    }
}

/// The big round button that starts or pauses pointing.
private struct CastButton: View {
    @ObservedObject var model: TelekinModel

    private var casting: Bool { model.status == .pointing }
    private var available: Bool { model.status == .pointing || model.status == .paused }

    var body: some View {
        Button(action: model.togglePause) {
            VStack(spacing: 6) {
                Image(systemName: casting ? "pause.fill" : "wand.and.stars").font(.system(size: 30, weight: .semibold))
                Text(casting ? "Pause" : "Cast").font(.title3.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(casting ? AnyShapeStyle(Color.white.opacity(0.1)) : AnyShapeStyle(Theme.spell)))
            .shadow(color: Theme.spellStart.opacity(casting ? 0 : 0.6), radius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(casting ? "Pause Telekin" : "Cast: start moving the cursor with your head")
        .accessibilityHint(available ? "Shortcut: Control Option P" : "Finish Setup first")
        .disabled(!available)
        .opacity(available ? 1 : 0.4)
        .help(available ? "⌃⌥P" : "Finish Setup first")
    }
}

private struct Stat: View {
    let value: Double
    let unit: String
    let label: String

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(unit).foregroundStyle(.white.opacity(0.5))
            }
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.rounded())) \(unit)")
    }
}

/// Starfield with a glowing wand tip that follows the head, leaving a fading trail. Clicks make a ring burst.
struct WandStage: View {
    @ObservedObject var model: TelekinModel
    @State private var stars: [CGPoint] = (0..<70).map { _ in CGPoint(x: .random(in: 0...1), y: .random(in: 0...1)) }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.07, green: 0.05, blue: 0.2), Color(red: 0.02, green: 0.02, blue: 0.08)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                drawStars(in: &context, size: size, time: time)
                drawGrid(in: &context, size: size)
                drawTrail(in: &context, size: size)
                drawBurst(in: &context, size: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Wand preview")
        .accessibilityValue(model.sample == nil ? "Waiting for your head" : "The glowing tip follows your head")
        .overlay(alignment: .topTrailing) {
            Button("Center") { model.zeroOrientation() }
                .accessibilityLabel("Center the wand")
                .padding(14)
                .help("Make the current head position the center")
        }
        .overlay(alignment: .bottomLeading) {
            Text(model.sample == nil ? "Waiting for your head…" : "Your head is the wand")
                .font(.caption).foregroundStyle(.white.opacity(0.55)).padding(14)
        }
    }

    private func point(_ unit: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + unit.x * size.width * 0.42, y: size.height / 2 - unit.y * size.height * 0.42)
    }

    private func drawStars(in context: inout GraphicsContext, size: CGSize, time: Double) {
        for (index, star) in stars.enumerated() {
            let twinkle = 0.35 + 0.35 * sin(time * 1.3 + Double(index))
            let rect = CGRect(x: star.x * size.width, y: star.y * size.height, width: 1.6, height: 1.6)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(twinkle)))
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for radius in [0.18, 0.32, 0.46] {
            let r = min(size.width, size.height) * radius
            context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.white.opacity(0.06)), lineWidth: 1)
        }
    }

    private func drawTrail(in context: inout GraphicsContext, size: CGSize) {
        let points = model.wandTrail.map { point($0, in: size) }
        guard let tip = points.last else { return }
        for index in points.indices.dropFirst() {
            let progress = Double(index) / Double(points.count)
            var segment = Path()
            segment.move(to: points[index - 1])
            segment.addLine(to: points[index])
            context.stroke(segment, with: .linearGradient(Gradient(colors: [Theme.spellStart, Theme.spellEnd]),
                                                          startPoint: points[index - 1], endPoint: points[index]),
                           style: StrokeStyle(lineWidth: 2 + 6 * progress, lineCap: .round))
            context.opacity = 1
        }
        var glow = context
        glow.addFilter(.blur(radius: 18))
        glow.fill(Path(ellipseIn: CGRect(x: tip.x - 26, y: tip.y - 26, width: 52, height: 52)), with: .color(Theme.spellEnd.opacity(0.8)))
        context.fill(Path(ellipseIn: CGRect(x: tip.x - 9, y: tip.y - 9, width: 18, height: 18)), with: .color(.white))
    }

    private func drawBurst(in context: inout GraphicsContext, size: CGSize) {
        let age = Date().timeIntervalSince(model.lastClickTime)
        guard age < 0.7, let tipUnit = model.wandTrail.last else { return }
        let tip = point(tipUnit, in: size)
        let rings = model.lastClick == .double ? 2 : 1
        for ring in 0..<rings {
            let localAge = age - Double(ring) * 0.12
            guard localAge > 0 else { continue }
            let radius = 12 + localAge * 160
            context.stroke(Path(ellipseIn: CGRect(x: tip.x - radius, y: tip.y - radius, width: 2 * radius, height: 2 * radius)),
                           with: .color(Theme.spark.opacity(max(0, 1 - localAge / 0.7))), lineWidth: 3)
        }
    }
}
