import Charts
import SwiftUI

/// Live head orientation (a 3D globe that turns with you) and a rotation-speed chart.
struct MotionView: View {
    @ObservedObject var model: TelekinModel

    var body: some View {
        Page(title: "Motion", subtitle: "What your AirPods feel, live.") {
            HStack(alignment: .top, spacing: 14) {
                Card("Head orientation") {
                    HeadGlobe(sample: model.sample, zeroYaw: model.zeroYaw, zeroPitch: model.zeroPitch)
                        .frame(height: 240)
                    HStack {
                        Angle3(label: "Turn", value: model.sample.map { MouseMapper.wrappedDegrees($0.yaw - model.zeroYaw) }, color: Theme.turn)
                        Angle3(label: "Nod", value: model.sample.map { $0.pitch - model.zeroPitch }, color: Theme.nod)
                        Angle3(label: "Tilt", value: model.sample?.roll, color: Theme.tilt)
                        Spacer()
                        Button("Zero", action: model.zeroOrientation).help("Make the current position zero")
                    }
                }
                Card("Signal") {
                    Row(label: "Updates", value: String(format: "%.0f per second", model.rateHz))
                    Row(label: "Cursor speed", value: String(format: "%.0f px/s", model.cursorSpeed))
                    Row(label: "Status", value: Theme.statusTitle(model.status))
                    Text("Head motion comes from Apple's headphone motion API while Telekin plays an inaudible spatial-audio tone.")
                        .font(.caption).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 250)
            }

            Card("Rotation speed (°/s)") {
                Chart(model.chart) { point in
                    LineMark(x: .value("Seconds", point.time), y: .value("°/s", point.value), series: .value("Axis", point.axis))
                        .foregroundStyle(by: .value("Axis", point.axis))
                        .interpolationMethod(.catmullRom)
                }
                .chartForegroundStyleScale(["Turn": Theme.turn, "Nod": Theme.nod, "Tilt": Theme.tilt])
                .chartXScale(domain: -TelekinModel.chartWindowSeconds...0)
                .chartYScale(domain: -120...120)
                .chartXAxis { AxisMarks(values: .stride(by: 1)) { _ in AxisGridLine().foregroundStyle(.white.opacity(0.08)) } }
                .chartYAxis {
                    AxisMarks(values: [-120, -60, 0, 60, 120]) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                        AxisValueLabel().foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(height: 220)
            }
        }
    }
}

private struct Angle3: View {
    let label: String
    let value: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(color)
            Text(value.map { String(format: "%+.0f°", $0) } ?? "–")
                .font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(.white).monospacedDigit()
        }
        .frame(width: 64, alignment: .leading)
    }
}

private struct Row: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value).foregroundStyle(.white).monospacedDigit()
        }
    }
}

/// A wireframe globe drawn in 3D: it turns, nods and tilts with your head. The bright arrow is where you face.
struct HeadGlobe: View {
    let sample: MotionSample?
    let zeroYaw: Double
    let zeroPitch: Double

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) * 0.4
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let rotation = Rotation(yaw: (sample.map { $0.yaw - zeroYaw } ?? 0), pitch: sample.map { $0.pitch - zeroPitch } ?? 0, roll: sample?.roll ?? 0)

            func project(_ p: Vector3) -> (CGPoint, Double) {
                let r = rotation.apply(p)
                let depth = 3.2 / (3.2 - r.z)
                return (CGPoint(x: center.x + r.x * radius * depth, y: center.y - r.y * radius * depth), r.z)
            }

            // Latitude and longitude rings.
            let rings: [[Vector3]] = (0..<5).map { lat in
                let phi = Double(lat - 2) * .pi / 6
                return (0...48).map { i in
                    let theta = Double(i) / 48 * 2 * .pi
                    return Vector3(x: cos(phi) * sin(theta), y: sin(phi), z: cos(phi) * cos(theta))
                }
            } + (0..<6).map { lon in
                let theta = Double(lon) * .pi / 6
                return (0...48).map { i in
                    let phi = Double(i) / 48 * 2 * .pi
                    return Vector3(x: cos(phi) * sin(theta), y: sin(phi), z: cos(phi) * cos(theta))
                }
            }
            for ring in rings {
                for index in ring.indices.dropFirst() {
                    let (a, za) = project(ring[index - 1])
                    let (b, zb) = project(ring[index])
                    var segment = Path()
                    segment.move(to: a)
                    segment.addLine(to: b)
                    let front = (za + zb) / 2 > 0
                    context.stroke(segment, with: .color(.white.opacity(front ? 0.35 : 0.08)), lineWidth: front ? 1.2 : 0.8)
                }
            }

            // Facing direction.
            let (tip, _) = project(Vector3(x: 0, y: 0, z: 1.45))
            let (base, _) = project(Vector3(x: 0, y: 0, z: 0))
            var arrow = Path()
            arrow.move(to: base)
            arrow.addLine(to: tip)
            var glow = context
            glow.addFilter(.blur(radius: 8))
            glow.stroke(arrow, with: .color(Theme.spellEnd), lineWidth: 8)
            context.stroke(arrow, with: .linearGradient(Gradient(colors: [Theme.spellStart, Theme.spellEnd]), startPoint: base, endPoint: tip),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: tip.x - 6, y: tip.y - 6, width: 12, height: 12)), with: .color(.white))
        }
    }
}

struct Vector3 {
    var x: Double, y: Double, z: Double
}

/// Yaw (turn), pitch (nod) and roll (tilt) as one rotation, all in degrees.
struct Rotation {
    let yaw: Double, pitch: Double, roll: Double

    func apply(_ v: Vector3) -> Vector3 {
        let (cy, sy) = (cos(yaw * .pi / 180), sin(yaw * .pi / 180))
        let (cp, sp) = (cos(pitch * .pi / 180), sin(pitch * .pi / 180))
        let (cr, sr) = (cos(roll * .pi / 180), sin(roll * .pi / 180))
        // Roll around the facing axis (z), then pitch around x, then yaw around the vertical (y).
        let r1 = Vector3(x: v.x * cr - v.y * sr, y: v.x * sr + v.y * cr, z: v.z)
        let r2 = Vector3(x: r1.x, y: r1.y * cp + r1.z * sp, z: -r1.y * sp + r1.z * cp)
        return Vector3(x: r2.x * cy - r2.z * sy, y: r2.y, z: r2.x * sy + r2.z * cy)
    }
}
