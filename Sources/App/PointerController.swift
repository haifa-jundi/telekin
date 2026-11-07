import Foundation

/// Connects head motion to the cursor: mapping, gliding, clicks, pause.
final class PointerController {
    static let tickInterval: TimeInterval = 1.0 / 120.0
    static let trustPollInterval: TimeInterval = 2.0

    enum Status: Equatable {
        case needsAccessibility
        case waitingForHeadphones
        case paused
        case pointing
        case failed(String)
    }

    enum ClickKind { case single, double }

    private(set) var snapshot: SettingsStore.Snapshot
    private(set) var paused = false
    /// Scroll mode (⌃⌥S): the cursor stays put and nods/turns scroll instead. Not saved between launches.
    private(set) var scrollMode = false
    var onScrollModeChange: ((Bool) -> Void)?
    private(set) var accessibilityTrusted = false
    private(set) var status: Status = .waitingForHeadphones { didSet { if status != oldValue { onStatusChange?(status) } } }

    /// Observers (the window, the menu bar, the spell trail). All called on the main thread.
    var onStatusChange: ((Status) -> Void)?
    var onSample: ((MotionSample) -> Void)?
    var onCursorMove: ((CGPoint, CGVector) -> Void)?
    var onClick: ((CGPoint, ClickKind) -> Void)?

    private let motion = HeadMotionSource()
    private let stemPresses = StemPressInput()
    private let store: SettingsStore
    private var mapper = MouseMapper()
    private var glide = CursorGlide()
    private var dwell = DwellClicker()
    private var tiltScroller = TiltScroller()
    /// Current head tilt from neutral, in degrees, for the live gauge.
    var currentTilt: Double { tiltScroller.tilt }
    private var lastPosted: CGPoint?
    private static let externalMoveTolerance: CGFloat = 3
    private var tickTimer: Timer?
    private var trustTimer: Timer?

    var settings: MouseSettings { snapshot.settings }
    var clicks: ClickOptions { snapshot.clicks }
    var effects: EffectOptions { snapshot.effects }
    var scroll: ScrollSettings { snapshot.scroll }
    var motionState: HeadMotionSource.State { motion.state }

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        snapshot = store.load()
        dwell.doubleClickEnabled = snapshot.clicks.dwellDoubleClick
    }

    func start() {
        accessibilityTrusted = CursorDriver.isTrusted(prompt: false)
        trustTimer = Timer.scheduledTimer(withTimeInterval: Self.trustPollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = CursorDriver.isTrusted(prompt: false)
            if trusted != self.accessibilityTrusted {
                self.accessibilityTrusted = trusted
                self.refreshStatus()
            }
        }
        motion.onPose = { [weak self] pose in self?.handle(pose) }
        motion.onSample = { [weak self] sample in
            self?.handleTilt(sample)
            self?.onSample?(sample)
        }
        motion.onStateChange = { [weak self] _ in self?.refreshStatus() }
        motion.start()
        stemPresses.onSinglePress = { [weak self] in self?.click(.single) ?? false }
        stemPresses.onDoublePress = { [weak self] in self?.click(.double) ?? false }
        stemPresses.setEnabled(snapshot.clicks.stemPress)
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        refreshStatus()
    }

    func stop() {
        tickTimer?.invalidate()
        trustTimer?.invalidate()
        stemPresses.setEnabled(false)
        motion.stop()
    }

    /// Shows the system Accessibility prompt (used by the setup screen).
    func requestAccessibility() {
        accessibilityTrusted = CursorDriver.isTrusted(prompt: true)
        refreshStatus()
    }

    /// Retries motion after the user fixed a permission or reconnected the AirPods.
    func restartMotion() {
        motion.stop()
        motion.start()
        refreshStatus()
    }

    func togglePause() {
        guard status == .pointing || status == .paused else { return }
        paused.toggle()
        resetMotionState()
        refreshStatus()
    }

    /// Clicks only while casting, so a paused or disconnected Telekin never clicks. Returns whether it clicked.
    @discardableResult
    func click(_ kind: ClickKind) -> Bool {
        guard status == .pointing else { return false }
        CursorDriver.click(count: kind == .double ? 2 : 1)
        onClick?(CursorDriver.position, kind)
        return true
    }

    func update(_ change: (inout SettingsStore.Snapshot) -> Void) {
        var copy = snapshot
        change(&copy)
        copy.settings.speed = copy.settings.speed.clamped(to: SettingsStore.speedRange)
        copy.settings.deadzoneDegreesPerSecond = copy.settings.deadzoneDegreesPerSecond.clamped(to: SettingsStore.deadzoneRange)
        copy.settings.acceleration = copy.settings.acceleration.clamped(to: SettingsStore.accelerationRange)
        copy.scroll.tiltDeadzoneDegrees = copy.scroll.tiltDeadzoneDegrees.clamped(to: SettingsStore.tiltDeadzoneRange)
        copy.scroll.speed = copy.scroll.speed.clamped(to: SettingsStore.scrollSpeedRange)
        let clicksChanged = copy.clicks != snapshot.clicks
        snapshot = copy
        if clicksChanged {
            dwell.doubleClickEnabled = copy.clicks.dwellDoubleClick
            dwell.reset()
            stemPresses.setEnabled(copy.clicks.stemPress)
        }
        store.save(copy)
    }

    func toggleScrollMode() {
        guard status == .pointing || scrollMode else { return }
        setScrollMode(!scrollMode)
    }

    /// Makes the current tilt the new neutral (used by the gauge's Center button and on recenter).
    func recenterTilt() { tiltScroller.reset() }

    private func setScrollMode(_ on: Bool) {
        guard on != scrollMode else { return }
        scrollMode = on
        glide.clear()
        dwell.reset()
        CursorDriver.resetScroll()
        onScrollModeChange?(on)
    }

    private func handle(_ pose: HeadPose) {
        guard status == .pointing else { return }
        let delta = mapper.delta(for: pose, settings: snapshot.settings)
        if scrollMode {
            CursorDriver.scroll(by: ScrollMode.wheel(fromCursorDelta: delta, settings: snapshot.scroll))
        } else {
            glide.add(delta)
        }
    }

    private func handleTilt(_ sample: MotionSample) {
        // Always tracked so the gauge stays live; only scrolls when enabled and casting outside scroll mode.
        let amount = tiltScroller.update(roll: sample.roll, time: sample.time, settings: snapshot.scroll)
        guard status == .pointing, snapshot.scroll.tiltScroll, !scrollMode, amount != 0 else { return }
        CursorDriver.scroll(by: CGVector(dx: 0, dy: amount))
    }

    private func tick() {
        guard status == .pointing else { return }
        let before = CursorDriver.position
        if let lastPosted, hypot(before.x - lastPosted.x, before.y - lastPosted.y) > Self.externalMoveTolerance {
            // Someone moved the mouse or trackpad: that motion must never arm a dwell click.
            dwell.reset()
        }
        let step = glide.step()
        let moved = step.dx != 0 || step.dy != 0
        let position = moved ? CursorDriver.move(by: step) : before
        lastPosted = position
        if moved { onCursorMove?(position, step) }
        guard snapshot.clicks.dwell else { return }
        switch dwell.update(position: position, time: ProcessInfo.processInfo.systemUptime) {
        case .click: click(.single)
        case .doubleClick: click(.double)
        case .none: break
        }
    }

    private func resetMotionState() {
        lastPosted = nil
        tiltScroller.reset()
        CursorDriver.resetScroll()
        mapper.reset()
        glide.clear()
        dwell.reset()
    }

    private func refreshStatus() {
        let next: Status
        if case .failed(let message) = motion.state {
            next = .failed(message)
        } else if !accessibilityTrusted {
            next = .needsAccessibility
        } else if motion.state != .streaming {
            next = .waitingForHeadphones
        } else if paused {
            next = .paused
        } else {
            next = .pointing
        }
        if next != status { resetMotionState() }
        if next != .pointing { setScrollMode(false) }
        status = next
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
