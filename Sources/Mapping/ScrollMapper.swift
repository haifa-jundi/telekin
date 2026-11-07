import CoreGraphics
import Foundation

/// User settings for scrolling with the head.
struct ScrollSettings: Equatable {
    /// Tilt (ear toward shoulder) to scroll up and down.
    var tiltScroll = false
    /// Tilts smaller than this many degrees from your neutral posture do nothing.
    var tiltDeadzoneDegrees: Double = 10
    /// Overall scroll speed multiplier.
    var speed: Double = 1.0
    /// Flip the scroll direction (both tilt and scroll mode).
    var reverse = false

    /// Points per second at `excess` degrees beyond the dead zone: 25 · excess^1.3 (10° ≈ 500 pt/s, 20° ≈ 1,230 pt/s).
    static let tiltGain = 25.0
    static let tiltExponent = 1.3
    /// How quickly neutral follows slow posture changes inside the dead zone.
    static let neutralFollowSeconds = 4.0
    /// Scroll mode: wheel points per point of would-be cursor motion.
    static let scrollModeFactor = 0.7
}

/// Tilt-to-scroll: turns head roll into a scroll amount for each motion sample.
///
/// Positive result scrolls up (content moves down), negative scrolls down, matching wheel units.
/// The first sample sets the neutral posture; while you stay inside the dead zone, neutral slowly
/// follows you, so leaning a little while reading never builds up into scrolling.
struct TiltScroller {
    static let maximumSampleGap: TimeInterval = 0.25

    private(set) var neutral: Double?
    private var lastTime: TimeInterval?
    /// Current tilt relative to neutral, in degrees (for the live gauge).
    private(set) var tilt: Double = 0

    mutating func reset() { self = TiltScroller() }

    /// Returns the scroll amount in points for the time since the previous sample.
    mutating func update(roll: Double, time: TimeInterval, settings: ScrollSettings) -> Double {
        defer { lastTime = time }
        guard let neutral else {
            self.neutral = roll
            tilt = 0
            return 0
        }
        tilt = MouseMapper.wrappedDegrees(roll - neutral)
        guard let lastTime, time > lastTime, time - lastTime <= Self.maximumSampleGap else { return 0 }
        let elapsed = time - lastTime
        let excess = abs(tilt) - settings.tiltDeadzoneDegrees
        guard excess > 0 else {
            // Inside the dead zone: let neutral drift toward the current posture.
            self.neutral = neutral + tilt * min(1, elapsed / ScrollSettings.neutralFollowSeconds)
            return 0
        }
        let pointsPerSecond = ScrollSettings.tiltGain * settings.speed * pow(excess, ScrollSettings.tiltExponent)
        let direction: Double = (tilt > 0 ? -1 : 1) * (settings.reverse ? -1 : 1)
        return direction * pointsPerSecond * elapsed
    }
}

/// Scroll mode: the cursor stays put and the motion that would have moved it scrolls instead.
enum ScrollMode {
    /// Converts a cursor delta (y down) to wheel deltas (positive = up / left, like a scroll wheel).
    static func wheel(fromCursorDelta delta: CGVector, settings: ScrollSettings) -> CGVector {
        let sign: CGFloat = settings.reverse ? 1 : -1
        let factor = CGFloat(ScrollSettings.scrollModeFactor * settings.speed)
        return CGVector(dx: sign * delta.dx * factor, dy: sign * delta.dy * factor)
    }
}
