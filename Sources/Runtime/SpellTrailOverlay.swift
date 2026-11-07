import AppKit
import QuartzCore

/// Sparkles that follow the cursor while Telekin steers it, and a burst on each click.
///
/// One transparent, click-through window per screen, each with a particle emitter.
/// The windows never take mouse events, so they can't block what you click.
final class SpellTrailOverlay {
    private static let idleDelay: TimeInterval = 0.15
    private static let trailBirthRate: Float = 90

    private var panes: [Pane] = []
    private var lastMove = Date.distantPast
    private var idleTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    var isEnabled = true {
        didSet { if !isEnabled { panes.forEach { $0.setTrail(on: false) } } }
    }

    init() {
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.lastMove) > Self.idleDelay else { return }
            self.panes.forEach { $0.setTrail(on: false) }
        }
    }

    deinit {
        idleTimer?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panes.forEach { $0.window.orderOut(nil) }
    }

    /// `point` is in global display coordinates (origin at the top-left of the main screen).
    func cursorMoved(to point: CGPoint) {
        guard isEnabled else { return }
        lastMove = Date()
        let cocoa = Self.cocoaPoint(point)
        for pane in panes {
            let inside = pane.window.frame.contains(cocoa)
            pane.setTrail(on: inside)
            if inside { pane.move(to: cocoa) }
        }
    }

    func burst(at point: CGPoint, double: Bool) {
        guard isEnabled else { return }
        let cocoa = Self.cocoaPoint(point)
        panes.first { $0.window.frame.contains(cocoa) }?.burst(at: cocoa, rings: double ? 2 : 1)
    }

    private func rebuild() {
        panes.forEach { $0.window.orderOut(nil) }
        panes = NSScreen.screens.map(Pane.init)
    }

    private static func cocoaPoint(_ point: CGPoint) -> CGPoint {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: mainHeight - point.y)
    }

    /// One screen's overlay window and its emitters.
    private final class Pane {
        let window: NSWindow
        private let trail = CAEmitterLayer()

        init(screen: NSScreen) {
            window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            window.contentView = view

            trail.emitterShape = .point
            trail.renderMode = .additive
            trail.emitterCells = [Self.cell(color: NSColor(calibratedRed: 0.62, green: 0.45, blue: 1, alpha: 1), birthRate: SpellTrailOverlay.trailBirthRate),
                                  Self.cell(color: NSColor(calibratedRed: 0.35, green: 0.9, blue: 1, alpha: 1), birthRate: SpellTrailOverlay.trailBirthRate * 0.6)]
            trail.birthRate = 0
            view.layer?.addSublayer(trail)
            window.orderFrontRegardless()
        }

        func setTrail(on: Bool) {
            let rate: Float = on ? 1 : 0
            if trail.birthRate != rate { trail.birthRate = rate }
        }

        func move(to cocoa: CGPoint) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            trail.emitterPosition = CGPoint(x: cocoa.x - window.frame.minX, y: cocoa.y - window.frame.minY)
            CATransaction.commit()
        }

        func burst(at cocoa: CGPoint, rings: Int) {
            guard let layer = window.contentView?.layer else { return }
            let local = CGPoint(x: cocoa.x - window.frame.minX, y: cocoa.y - window.frame.minY)
            for ring in 0..<rings {
                let burst = CAEmitterLayer()
                burst.emitterPosition = local
                burst.emitterShape = .circle
                burst.emitterSize = CGSize(width: 6, height: 6)
                burst.renderMode = .additive
                let spark = Self.cell(color: NSColor(calibratedRed: 1, green: 0.86, blue: 0.45, alpha: 1), birthRate: 900)
                spark.velocity = 220
                spark.velocityRange = 80
                spark.emissionRange = .pi * 2
                spark.lifetime = 0.55
                burst.emitterCells = [spark]
                burst.beginTime = CACurrentMediaTime() + Double(ring) * 0.12
                layer.addSublayer(burst)
                // Emit for a blink, then let the sparks fade out and remove the layer.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 + Double(ring) * 0.12) { burst.birthRate = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + Double(ring) * 0.12) { burst.removeFromSuperlayer() }
            }
        }

        private static let dot: CGImage? = {
            let size = 16
            guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])
            else { return nil }
            let center = CGPoint(x: size / 2, y: size / 2)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(size) / 2, options: [])
            return context.makeImage()
        }()

        private static func cell(color: NSColor, birthRate: Float) -> CAEmitterCell {
            let cell = CAEmitterCell()
            cell.contents = dot
            cell.color = color.cgColor
            cell.birthRate = birthRate
            cell.lifetime = 0.7
            cell.lifetimeRange = 0.3
            cell.velocity = 30
            cell.velocityRange = 25
            cell.emissionRange = .pi * 2
            cell.scale = 0.35
            cell.scaleRange = 0.2
            cell.scaleSpeed = -0.4
            cell.alphaSpeed = -1.4
            return cell
        }
    }
}
