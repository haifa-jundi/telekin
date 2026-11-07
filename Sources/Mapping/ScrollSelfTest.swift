import CoreGraphics
import Foundation

extension MappingSelfTest {
    /// Feeds a constant tilt for `seconds` at 50 Hz after a neutral sample; returns total scroll in points.
    private static func scrollFor(tilt: Double, seconds: Double, settings: ScrollSettings = ScrollSettings()) -> Double {
        var scroller = TiltScroller()
        _ = scroller.update(roll: 0, time: 0, settings: settings) // neutral
        var total = 0.0
        var t = 0.0
        while t < seconds {
            t += 0.02
            total += scroller.update(roll: tilt, time: t, settings: settings)
        }
        return total
    }

    static func runScrollChecks() {
        // Tilt inside the dead zone does nothing.
        check(scrollFor(tilt: 6, seconds: 1) == 0, "small tilt does not scroll")

        // Tilting right scrolls down (negative = down, like a wheel), left scrolls up.
        let right = scrollFor(tilt: 20, seconds: 1)
        let left = scrollFor(tilt: -20, seconds: 1)
        check(right < 0 && left > 0, "tilt right scrolls down, left scrolls up")

        // More tilt scrolls faster.
        check(abs(scrollFor(tilt: 30, seconds: 1)) > abs(right), "more tilt scrolls faster")

        // Reverse flips direction.
        var reversed = ScrollSettings(); reversed.reverse = true
        check(scrollFor(tilt: 20, seconds: 1, settings: reversed) > 0, "reverse flips tilt scroll")

        // The first sample sets neutral: a head that starts tilted does not scroll.
        var leaning = TiltScroller()
        var leanTotal = 0.0
        for i in 0..<50 { leanTotal += leaning.update(roll: 15, time: Double(i) * 0.02, settings: ScrollSettings()) }
        check(leanTotal == 0, "starting tilt becomes neutral")

        // Slow posture drift inside the dead zone moves neutral, so it never builds up into scrolling.
        var drifting = TiltScroller()
        var driftTotal = 0.0
        for i in 0...3000 { // 60 s, drifting to 14 degrees at 0.23 deg/s
            let t = Double(i) * 0.02
            driftTotal += drifting.update(roll: min(14, t * 0.23), time: t, settings: ScrollSettings())
        }
        check(driftTotal == 0, "slow posture drift never scrolls")

        // A gap in samples does not produce a burst.
        var gapped = TiltScroller()
        _ = gapped.update(roll: 0, time: 0, settings: ScrollSettings())
        check(gapped.update(roll: 30, time: 2, settings: ScrollSettings()) == 0, "sample gap gives no scroll burst")

        // Scroll mode: looking down (cursor delta down) scrolls down; turning right scrolls right.
        let down = ScrollMode.wheel(fromCursorDelta: CGVector(dx: 0, dy: 10), settings: ScrollSettings())
        check(down.dy < 0 && down.dx == 0, "scroll mode: nod down scrolls down")
        let rightTurn = ScrollMode.wheel(fromCursorDelta: CGVector(dx: 10, dy: 0), settings: ScrollSettings())
        check(rightTurn.dx < 0, "scroll mode: turn right scrolls right")
        check(ScrollMode.wheel(fromCursorDelta: CGVector(dx: 0, dy: 10), settings: reversed).dy > 0, "scroll mode honours reverse")
    }
}
