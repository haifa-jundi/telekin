import ApplicationServices
import CoreGraphics

/// Moves the system cursor and clicks by posting mouse events. Needs the Accessibility permission.
enum CursorDriver {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Current cursor position in global display coordinates (origin top-left).
    static var position: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Moves the cursor by `delta`, kept on screen. Returns the new position.
    @discardableResult
    static func move(by delta: CGVector) -> CGPoint {
        let current = position
        let target = clampToDisplays(CGPoint(x: current.x + delta.dx, y: current.y + delta.dy), from: current)
        // While the left button is held (trackpad click-and-hold), the move must be a drag.
        let dragging = CGEventSource.buttonState(.combinedSessionState, button: .left)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: dragging ? .leftMouseDragged : .mouseMoved,
                                  mouseCursorPosition: target, mouseButton: .left) else { return current }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64((target.x - current.x).rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64((target.y - current.y).rounded()))
        event.post(tap: .cghidEventTap)
        return target
    }

    /// Left click; `count` 2 sends a double-click (apps read the click count from each event).
    static func click(count: Int = 1) {
        let point = position
        for clickNumber in 1...max(1, count) {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { continue }
                event.setIntegerValueField(.mouseEventClickState, value: Int64(clickNumber))
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// Keeps the point on the display it is on, or on the display the cursor came from.
    static func clampToDisplays(_ point: CGPoint, from origin: CGPoint) -> CGPoint {
        let displays = activeDisplayBounds()
        if displays.contains(where: { $0.contains(point) }) { return point }
        guard let home = displays.first(where: { $0.contains(origin) }) ?? displays.first else { return point }
        return CGPoint(x: min(max(point.x, home.minX), home.maxX - 1), y: min(max(point.y, home.minY), home.maxY - 1))
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }
}
