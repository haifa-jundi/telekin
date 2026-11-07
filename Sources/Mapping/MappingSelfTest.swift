import CoreGraphics
import Foundation

/// Offline checks for the mapping logic. Run with `Telekin --self-test`; exits non-zero on failure.
enum MappingSelfTest {
    static var failures: [String] = []

    static func check(_ condition: Bool, _ name: String) {
        if !condition { failures.append(name) }
    }

    private static func feed(_ mapper: inout MouseMapper, _ poses: [(Double, Double, Double)], _ settings: MouseSettings = MouseSettings()) -> CGVector {
        var total = CGVector.zero
        for (yaw, pitch, time) in poses {
            let d = mapper.delta(for: HeadPose(yaw: yaw, pitch: pitch, time: time), settings: settings)
            total = CGVector(dx: total.dx + d.dx, dy: total.dy + d.dy)
        }
        return total
    }

    static func run() -> Int32 {
        failures = []

        // Angle wrapping.
        check(abs(MouseMapper.wrappedDegrees(358) - (-2)) < 1e-9, "wrap 358 -> -2")
        check(abs(MouseMapper.wrappedDegrees(-358) - 2) < 1e-9, "wrap -358 -> 2")
        check(MouseMapper.wrappedDegrees(180) == 180, "wrap 180 stays 180")

        // First sample gives no movement.
        var mapper = MouseMapper()
        check(mapper.delta(for: HeadPose(yaw: 0, pitch: 0, time: 0), settings: MouseSettings()) == .zero, "first sample is zero")

        // Turning left (yaw increasing) moves the cursor left; looking up moves it up.
        mapper = MouseMapper()
        let left = feed(&mapper, [(0, 0, 0), (1, 0, 0.02), (2, 0, 0.04)])
        check(left.dx < 0 && abs(left.dy) < 1e-9, "turn left moves cursor left")
        mapper = MouseMapper()
        let up = feed(&mapper, [(0, 0, 0), (0, 1, 0.02), (0, 2, 0.04)])
        check(up.dy < 0 && abs(up.dx) < 1e-9, "look up moves cursor up")

        // Inversion flips direction.
        var inverted = MouseSettings(); inverted.invertHorizontal = true; inverted.invertVertical = true
        mapper = MouseMapper()
        let flipped = feed(&mapper, [(0, 0, 0), (1, 1, 0.02)], inverted)
        check(flipped.dx > 0 && flipped.dy > 0, "inversion flips both axes")

        // Slow drift inside the dead zone is ignored (1 deg/s < 2.5 deg/s).
        mapper = MouseMapper()
        let drift = feed(&mapper, [(0, 0, 0), (0.02, 0, 0.02), (0.04, 0, 0.04)])
        check(drift == .zero, "drift below dead zone ignored")

        // A gap in samples is not treated as a jump.
        mapper = MouseMapper()
        let gap = feed(&mapper, [(0, 0, 0), (30, 0, 1.0)])
        check(gap == .zero, "sample gap gives no jump")

        // Wrap-around turn is small, not a 358 degree swing.
        mapper = MouseMapper()
        let wrap = feed(&mapper, [(179, 0, 0), (-179, 0, 0.02)])
        check(wrap.dx < 0 && abs(wrap.dx) < 2 * 16 * 3, "wrap-around turn stays small")

        // Acceleration: the same angle turned faster moves further.
        var flat = MouseSettings(); flat.deadzoneDegreesPerSecond = 0
        mapper = MouseMapper()
        let slow = feed(&mapper, [(0, 0, 0), (2, 0, 0.1)], flat)
        mapper = MouseMapper()
        let fast = feed(&mapper, [(0, 0, 0), (2, 0, 0.01)], flat)
        check(abs(fast.dx) > abs(slow.dx), "faster turn moves further")

        // Speed setting scales output.
        var double = flat; double.speed = 2
        mapper = MouseMapper()
        let doubled = feed(&mapper, [(0, 0, 0), (2, 0, 0.1)], double)
        check(abs(abs(doubled.dx) - 2 * abs(slow.dx)) < 1e-6, "speed doubles movement")

        // Glide releases everything it was given, and settles at zero.
        var glide = CursorGlide()
        glide.add(CGVector(dx: 100, dy: -50))
        var released = CGVector.zero
        for _ in 0..<60 { let s = glide.step(); released = CGVector(dx: released.dx + s.dx, dy: released.dy + s.dy) }
        check(abs(released.dx - 100) < 1e-6 && abs(released.dy + 50) < 1e-6, "glide releases full delta")
        check(glide.pending == .zero, "glide settles")

        // Dwell: no click without travel.
        var dwell = DwellClicker()
        var events: [(DwellClicker.Event, Double)] = []
        for i in 0..<200 {
            let e = dwell.update(position: CGPoint(x: 10, y: 10), time: Double(i) * 0.02)
            if e != .none { events.append((e, Double(i) * 0.02)) }
        }
        check(events.isEmpty, "dwell needs travel first")

        // Move, then hold 1.5 s: exactly one click, near 1 s, no double-click.
        func moveThenHold(seconds: Double) -> [(DwellClicker.Event, Double)] {
            var clicker = DwellClicker()
            var found: [(DwellClicker.Event, Double)] = []
            var t = 0.0
            for x in stride(from: 0.0, through: 200.0, by: 10.0) { _ = clicker.update(position: CGPoint(x: x, y: 0), time: t); t += 0.02 }
            let holdStart = t
            while t - holdStart < seconds {
                let e = clicker.update(position: CGPoint(x: 200, y: 1), time: t)
                if e != .none { found.append((e, t - holdStart)) }
                t += 0.02
            }
            return found
        }
        let short = moveThenHold(seconds: 1.5)
        check(short.count == 1 && short[0].0 == .click && abs(short[0].1 - 0.9) < 0.1, "1 s hold clicks once")

        // Hold 3 s: click near 1 s, then one double-click near 2 s, nothing after.
        let long = moveThenHold(seconds: 3.0)
        check(long.count == 2 && long[0].0 == .click && long[1].0 == .doubleClick && abs(long[1].1 - 1.9) < 0.1,
              "2 s hold adds one double-click")

        // Without the double-click option, a long hold only clicks once.
        var single = DwellClicker(); single.doubleClickEnabled = false
        var singleEvents = 0
        var st = 0.0
        for x in stride(from: 0.0, through: 200.0, by: 10.0) { _ = single.update(position: CGPoint(x: x, y: 0), time: st); st += 0.02 }
        for _ in 0..<150 { if single.update(position: CGPoint(x: 200, y: 0), time: st) != .none { singleEvents += 1 }; st += 0.02 }
        check(singleEvents == 1, "double-click can be turned off")

        runScrollChecks()

        if failures.isEmpty {
            print("PASS: mapping self-test (wrap, direction, inversion, dead zone, gaps, acceleration, speed, glide, dwell click and double-click, tilt scroll, scroll mode)")
            return 0
        }
        print("FAIL: " + failures.joined(separator: "; "))
        return 1
    }
}
