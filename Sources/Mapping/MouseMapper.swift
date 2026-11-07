import CoreGraphics
import Foundation

/// User-tunable settings for turning head motion into cursor motion.
struct MouseSettings: Equatable {
    /// Overall speed multiplier (1 = normal).
    var speed: Double = 1.0
    /// Head turns slower than this (degrees per second) are ignored, which hides sensor drift and small tremors.
    var deadzoneDegreesPerSecond: Double = 2.5
    /// How much faster the cursor goes for fast head turns (0 = linear).
    var acceleration: Double = 0.6
    var invertHorizontal = false
    var invertVertical = false

    static let pixelsPerDegree = 16.0
    static let accelerationReferenceDegreesPerSecond = 60.0
    static let accelerationCapDegreesPerSecond = 240.0
}

/// Everything the live views show about one motion sample: angles in degrees, rates in degrees per second.
struct MotionSample: Equatable {
    let yaw: Double
    let pitch: Double
    let roll: Double
    let yawRate: Double
    let pitchRate: Double
    let rollRate: Double
    let time: TimeInterval
}

/// One head-pose sample, in degrees.
struct HeadPose: Equatable {
    let yaw: Double
    let pitch: Double
    let time: TimeInterval
}

/// Turns successive head poses into cursor deltas (mouse mode: relative, with acceleration).
///
/// Turning the head left moves the cursor left; looking up moves it up.
struct MouseMapper {
    /// Samples further apart than this are treated as a gap, not a movement.
    static let maximumSampleGap: TimeInterval = 0.25

    private(set) var previous: HeadPose?

    mutating func reset() { previous = nil }

    /// Returns the cursor delta in points (screen coordinates, y grows downward).
    mutating func delta(for pose: HeadPose, settings: MouseSettings) -> CGVector {
        defer { previous = pose }
        guard let previous else { return .zero }
        let elapsed = pose.time - previous.time
        guard elapsed > 0, elapsed <= Self.maximumSampleGap else { return .zero }

        let yawChange = Self.wrappedDegrees(pose.yaw - previous.yaw)
        let pitchChange = Self.wrappedDegrees(pose.pitch - previous.pitch)
        let angularSpeed = hypot(yawChange, pitchChange) / elapsed
        guard angularSpeed > settings.deadzoneDegreesPerSecond else { return .zero }

        // Soft dead zone: motion just above the threshold starts from zero instead of jumping.
        let deadzoneScale = (angularSpeed - settings.deadzoneDegreesPerSecond) / angularSpeed
        let cappedSpeed = min(angularSpeed, MouseSettings.accelerationCapDegreesPerSecond)
        let gain = MouseSettings.pixelsPerDegree * settings.speed
            * (1 + settings.acceleration * cappedSpeed / MouseSettings.accelerationReferenceDegreesPerSecond)

        let horizontal = -yawChange * deadzoneScale * gain * (settings.invertHorizontal ? -1 : 1)
        let vertical = -pitchChange * deadzoneScale * gain * (settings.invertVertical ? -1 : 1)
        return CGVector(dx: horizontal, dy: vertical)
    }

    /// Maps an angle difference into (-180, 180] so a wrap from 179° to -179° reads as 2°.
    static func wrappedDegrees(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result <= -180 { result += 360 }
        return result
    }
}

/// Spreads the 50 Hz motion deltas over a faster display tick so the cursor glides instead of stepping.
struct CursorGlide {
    /// Fraction of the remaining distance released on each tick.
    static let releaseFraction = 0.35
    static let snapDistance = 0.5

    private(set) var pending = CGVector.zero

    mutating func add(_ delta: CGVector) {
        pending = CGVector(dx: pending.dx + delta.dx, dy: pending.dy + delta.dy)
    }

    mutating func clear() { pending = .zero }

    /// Returns the step to apply on this tick.
    mutating func step() -> CGVector {
        let remaining = hypot(pending.dx, pending.dy)
        let step: CGVector
        if remaining <= Self.snapDistance {
            step = pending
        } else {
            step = CGVector(dx: pending.dx * Self.releaseFraction, dy: pending.dy * Self.releaseFraction)
        }
        pending = CGVector(dx: pending.dx - step.dx, dy: pending.dy - step.dy)
        return step
    }
}

/// Dwell click: after the cursor travels somewhere and then holds still, click once.
struct DwellClicker {
    static let holdRadius: CGFloat = 8
    static let armingTravel: CGFloat = 40
    static let holdDuration: TimeInterval = 0.9

    private var anchor: CGPoint?
    private var anchorTime: TimeInterval = 0
    private var travelSinceClick: CGFloat = 0
    private var lastPoint: CGPoint?

    enum Event: Equatable {
        case none
        case click
        /// Sent after the click when the hold continues; apps see it as a double-click.
        case doubleClick
    }

    /// Total hold time (from the start of the hold) that adds a double-click.
    static let doubleClickHoldDuration: TimeInterval = 1.9

    /// When false, a long hold only ever clicks once.
    var doubleClickEnabled = true
    private var clickedThisHold = false
    private var doubleClickedThisHold = false

    mutating func reset() {
        let keepDouble = doubleClickEnabled
        self = DwellClicker()
        doubleClickEnabled = keepDouble
    }

    /// Feeds the current cursor position; returns a click or double-click exactly when one should happen.
    mutating func update(position: CGPoint, time: TimeInterval) -> Event {
        if let lastPoint { travelSinceClick += hypot(position.x - lastPoint.x, position.y - lastPoint.y) }
        lastPoint = position
        guard let anchor, hypot(position.x - anchor.x, position.y - anchor.y) <= Self.holdRadius else {
            // Moved away: a new hold can start here.
            self.anchor = position
            anchorTime = time
            clickedThisHold = false
            doubleClickedThisHold = false
            return .none
        }
        let held = time - anchorTime
        if !clickedThisHold, travelSinceClick >= Self.armingTravel, held >= Self.holdDuration {
            clickedThisHold = true
            travelSinceClick = 0
            return .click
        }
        if clickedThisHold, doubleClickEnabled, !doubleClickedThisHold, held >= Self.doubleClickHoldDuration {
            doubleClickedThisHold = true
            return .doubleClick
        }
        return .none
    }
}
