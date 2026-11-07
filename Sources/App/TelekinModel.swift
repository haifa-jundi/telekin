import Combine
import CoreMotion
import Foundation
import SwiftUI

/// Live state for the window. Motion arrives at ~50 Hz; the views refresh at 30 Hz from a snapshot.
final class TelekinModel: ObservableObject {
    static let publishInterval: TimeInterval = 1.0 / 30.0
    static let chartWindowSeconds: Double = 6
    static let wandTrailLength = 48

    struct ChartPoint: Identifiable {
        let id: Int
        let time: Double
        let axis: String
        let value: Double
    }

    let controller: PointerController

    @Published private(set) var status: PointerController.Status = .waitingForHeadphones
    @Published private(set) var sample: MotionSample?
    @Published private(set) var rateHz: Double = 0
    @Published private(set) var cursorSpeed: Double = 0
    @Published private(set) var chart: [ChartPoint] = []
    /// Recent wand-tip positions in -1...1 (x right, y up), newest last.
    @Published private(set) var wandTrail: [CGPoint] = []
    @Published private(set) var clickCount = 0
    @Published private(set) var lastClick: PointerController.ClickKind?
    @Published private(set) var lastClickTime = Date.distantPast
    @Published private(set) var snapshot: SettingsStore.Snapshot
    @Published var zeroYaw: Double = 0
    @Published var zeroPitch: Double = 0
    @Published var section: Section = .home
    /// Live views only update while the window is on screen.
    var windowVisible = false

    private var latest: MotionSample?
    private var samplesThisWindow = 0
    private var windowStart = Date()
    private var cursorTravel: Double = 0
    private var chartBuffer: [(time: Double, sample: MotionSample)] = []
    private var timer: Timer?

    init(controller: PointerController) {
        self.controller = controller
        snapshot = controller.snapshot
        status = controller.status
        controller.onSample = { [weak self] sample in self?.receive(sample) }
        let timer = Timer(timeInterval: Self.publishInterval, repeats: true) { [weak self] _ in self?.publish() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    // MARK: Inputs from the controller

    func statusChanged(_ status: PointerController.Status) {
        self.status = status
        snapshot = controller.snapshot
    }

    func cursorMoved(by step: CGVector) { cursorTravel += hypot(step.dx, step.dy) }

    func clicked(_ kind: PointerController.ClickKind) {
        clickCount += 1
        lastClick = kind
        lastClickTime = Date()
    }

    /// Feeds recorded or synthetic motion straight in (used to render README screenshots).
    func replay(_ samples: [MotionSample], rate: Double, cursorSpeed: Double, clicks: Int) {
        windowVisible = true
        for sample in samples {
            receive(sample)
            if let latest { wandTrail.append(wandTip(for: latest)) }
        }
        if wandTrail.count > Self.wandTrailLength { wandTrail.removeFirst(wandTrail.count - Self.wandTrailLength) }
        sample = latest
        rateHz = rate
        self.cursorSpeed = cursorSpeed
        clickCount = clicks
        if let last = samples.last { rebuildChart(endingAt: last.time) }
    }

    private func receive(_ sample: MotionSample) {
        latest = sample
        samplesThisWindow += 1
        chartBuffer.append((sample.time, sample))
        let cutoff = sample.time - Self.chartWindowSeconds
        if let first = chartBuffer.first, first.time < cutoff {
            chartBuffer.removeAll { $0.time < cutoff }
        }
    }

    private func publish() {
        // Settings can also change from the menu bar; keep the window in step.
        if controller.snapshot != snapshot { snapshot = controller.snapshot }
        let now = Date()
        let elapsed = now.timeIntervalSince(windowStart)
        if elapsed >= 0.5 {
            rateHz = Double(samplesThisWindow) / elapsed
            cursorSpeed = cursorTravel / elapsed
            samplesThisWindow = 0
            cursorTravel = 0
            windowStart = now
        }
        guard windowVisible, let latest, latest != sample else { return }
        sample = latest
        wandTrail.append(wandTip(for: latest))
        if wandTrail.count > Self.wandTrailLength { wandTrail.removeFirst(wandTrail.count - Self.wandTrailLength) }
        rebuildChart(endingAt: latest.time)
    }

    /// Maps head angles to the wand canvas: ±35° of turn or nod reaches the edge.
    func wandTip(for sample: MotionSample) -> CGPoint {
        let reach = 35.0
        let x = -MouseMapper.wrappedDegrees(sample.yaw - zeroYaw) / reach
        let y = MouseMapper.wrappedDegrees(sample.pitch - zeroPitch) / reach
        return CGPoint(x: x.clamped(to: -1...1), y: y.clamped(to: -1...1))
    }

    private func rebuildChart(endingAt end: Double) {
        // Every other sample keeps the chart light (~25 points per second per line).
        var points: [ChartPoint] = []
        points.reserveCapacity(chartBuffer.count * 2)
        for (index, entry) in chartBuffer.enumerated() where index % 2 == 0 {
            let t = entry.time - end
            // Stable ids (from the sample's own timestamp) let SwiftUI diff instead of redrawing everything.
            let key = Int((entry.time * 1000).rounded()) * 3
            points.append(ChartPoint(id: key, time: t, axis: "Turn", value: entry.sample.yawRate))
            points.append(ChartPoint(id: key + 1, time: t, axis: "Nod", value: entry.sample.pitchRate))
            points.append(ChartPoint(id: key + 2, time: t, axis: "Tilt", value: entry.sample.rollRate))
        }
        chart = points
    }

    // MARK: Actions from the views

    func zeroOrientation() {
        guard let sample else { return }
        zeroYaw = sample.yaw
        zeroPitch = sample.pitch
        wandTrail.removeAll()
    }

    func togglePause() { controller.togglePause() }
    func click(_ kind: PointerController.ClickKind) { controller.click(kind) }

    func update(_ change: (inout SettingsStore.Snapshot) -> Void) {
        controller.update(change)
        snapshot = controller.snapshot
    }

    /// A two-way binding into the saved settings, for sliders and toggles.
    func binding<Value>(_ keyPath: WritableKeyPath<SettingsStore.Snapshot, Value>) -> Binding<Value> {
        Binding(get: { self.snapshot[keyPath: keyPath] },
                set: { value in self.update { $0[keyPath: keyPath] = value } })
    }

    // MARK: Setup checks

    var motionAuthorized: Bool { CMHeadphoneMotionManager.authorizationStatus() == .authorized }
    var accessibilityTrusted: Bool { controller.accessibilityTrusted }
    var airPodsStreaming: Bool { controller.motionState == .streaming }
    var isReady: Bool { motionAuthorized && accessibilityTrusted && airPodsStreaming }
}
