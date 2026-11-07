import AVFAudio
import CoreMotion
import Foundation

/// Streams AirPods head pose through Apple's public CoreMotion API.
///
/// macOS only shares head pose while the app plays spatialized audio, so this
/// also plays a near-silent tone through a head-tracked 3D audio node.
final class HeadMotionSource: NSObject, CMHeadphoneMotionManagerDelegate {
    enum State: Equatable {
        case stopped
        case waitingForHeadphones
        case streaming
        case failed(String)
    }

    var onPose: ((HeadPose) -> Void)?
    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .stopped { didSet { if state != oldValue { onStateChange?(state) } } }

    private let manager = CMHeadphoneMotionManager()
    private var audio: SpatialKeepAlive?

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        guard state == .stopped || isFailed else { return }
        guard manager.isDeviceMotionAvailable else {
            state = .failed("Headphone motion is not available on this Mac")
            return
        }
        if CMHeadphoneMotionManager.authorizationStatus() == .denied || CMHeadphoneMotionManager.authorizationStatus() == .restricted {
            state = .failed("Motion access is off: System Settings › Privacy & Security › Motion & Fitness")
            return
        }
        do {
            audio = try SpatialKeepAlive()
        } catch {
            state = .failed("Spatial audio could not start: \(error.localizedDescription)")
            return
        }
        state = .waitingForHeadphones
        startUpdates()
        // Updates started before the Motion prompt is answered stay silent, so restart them once it is.
        if CMHeadphoneMotionManager.authorizationStatus() == .notDetermined {
            authorizationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                let status = CMHeadphoneMotionManager.authorizationStatus()
                guard status != .notDetermined else { return }
                timer.invalidate()
                if status == .authorized, self.state == .waitingForHeadphones {
                    self.manager.stopDeviceMotionUpdates()
                    self.startUpdates()
                } else if status != .authorized {
                    self.stop()
                    self.state = .failed("Motion access is off: System Settings › Privacy & Security › Motion & Fitness")
                }
            }
        }
    }

    private var authorizationTimer: Timer?

    private func startUpdates() {
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                NSLog("Telekin motion error: %@", error.localizedDescription)
                return
            }
            guard let motion else { return }
            if self.state != .streaming { self.state = .streaming }
            let degrees = 180 / Double.pi
            let pose = HeadPose(yaw: motion.attitude.yaw * degrees, pitch: motion.attitude.pitch * degrees, time: motion.timestamp)
            self.onPose?(pose)
            self.onSample?(MotionSample(
                yaw: pose.yaw, pitch: pose.pitch, roll: motion.attitude.roll * degrees,
                yawRate: motion.rotationRate.z * degrees, pitchRate: motion.rotationRate.x * degrees,
                rollRate: motion.rotationRate.y * degrees, time: motion.timestamp))
        }
    }

    /// Full motion for the live views; `onPose` stays the lean path for the cursor.
    var onSample: ((MotionSample) -> Void)?

    func stop() {
        authorizationTimer?.invalidate()
        authorizationTimer = nil
        manager.stopDeviceMotionUpdates()
        audio?.stop()
        audio = nil
        state = .stopped
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        if state == .stopped || isFailed { return }
        audio?.restartIfNeeded()
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        if state == .stopped || isFailed { return }
        state = .waitingForHeadphones
    }
}

/// Plays a near-silent tone through a head-tracked spatial audio node so macOS shares head pose.
final class SpatialKeepAlive {
    private static let sampleRate = 48_000.0
    private static let toneHertz: Float = 440
    /// About -66 dB: inaudible in practice, but real audio as far as the system is concerned.
    private static let amplitude: Float = 0.0005

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer

    init() throws {
        let environment = AVAudioEnvironmentNode()
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(Self.sampleRate)),
              let samples = buffer.floatChannelData?[0] else {
            throw NSError(domain: "Telekin", code: 1, userInfo: [NSLocalizedDescriptionKey: "audio buffer unavailable"])
        }
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) {
            samples[index] = Self.amplitude * sinf(2 * .pi * Self.toneHertz * Float(index) / Float(Self.sampleRate))
        }
        self.buffer = buffer
        engine.attach(environment)
        engine.attach(player)
        engine.connect(player, to: environment, format: mono)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        environment.outputType = .headphones
        environment.isListenerHeadTrackingEnabled = true
        player.renderingAlgorithm = .HRTFHQ
        player.position = AVAudio3DPoint(x: 0, y: 0, z: -1)
        try engine.start()
        play()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.restartIfNeeded() }
    }

    private var configurationObserver: NSObjectProtocol?

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    private func play() {
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
    }

    /// Output-device changes (AirPods reconnecting) stop the engine; start it again.
    func restartIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            play()
        } catch {
            NSLog("Telekin could not restart spatial audio: %@", error.localizedDescription)
        }
    }

    func stop() {
        player.stop()
        engine.stop()
    }
}
