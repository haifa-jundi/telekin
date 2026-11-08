import AVFoundation
import Foundation
import os
import Speech

/// Listens for spoken commands with Apple's on-device speech recognition. Audio never leaves the Mac:
/// if this Mac can only recognise speech on Apple's servers, voice commands stay off.
final class VoiceListener: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    enum Permission: Equatable {
        case microphone, speech

        var settingsURL: URL? {
            let pane = self == .microphone ? "Privacy_Microphone" : "Privacy_SpeechRecognition"
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        }
    }

    enum State: Equatable {
        case off
        case listening
        case denied(Permission)
        case unavailable(String)
    }

    /// Silence that ends an utterance. Only then is it checked for commands.
    static let utterancePause: TimeInterval = 0.6
    /// An idle recognition task is replaced this often so it never hits the recogniser's time limit.
    static let taskLifetime: TimeInterval = 50
    static let retryDelay: TimeInterval = 0.5
    static let maxRetryDelay: TimeInterval = 8
    /// A task that fails within this long counts as a failure; this many in a row turns voice off.
    static let quickFailure: TimeInterval = 1
    static let maxFailures = 6

    /// Diagnostics only: states, errors and which command matched. Never what you said.
    private static let log = Logger(subsystem: "io.github.haifa-jundi.telekin", category: "voice")

    var onCommand: ((VoiceCommand) -> Void)?
    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .off {
        didSet {
            guard state != oldValue else { return }
            Self.log.notice("state \(String(describing: self.state), privacy: .public)")
            onStateChange?(state)
        }
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    /// Audio comes from a capture session on a chosen microphone (see `MicrophonePicker`), never the AirPods.
    private var session: AVCaptureSession?
    private let audioQueue = DispatchQueue(label: "io.github.haifa-jundi.telekin.voice-audio")
    private var deviceObservers: [NSObjectProtocol] = []
    private var task: SFSpeechRecognitionTask?
    private var taskStarted = Date()
    /// What the current task has heard so far: one utterance, since each task ends at a pause.
    private var utterance = ""
    private var settleTimer: Timer?
    private var failures = 0
    private var wanted = false
    /// Bumped on every switch on or off, so a permission answer for an old switch is ignored.
    private var enableGeneration = 0
    /// Bumped whenever a task is replaced, so late results from an old task are ignored.
    private var generation = 0
    private var renewTimer: Timer?

    /// The audio tap runs on its own thread: it appends under this lock, and the request is swapped under it.
    private let requestLock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    /// Puts `next` in place and ends the old request, which the tap can no longer reach.
    private func swapRequest(_ next: SFSpeechAudioBufferRecognitionRequest?) {
        let old = requestLock.withLock { () -> SFSpeechAudioBufferRecognitionRequest? in
            let old = request
            request = next
            return old
        }
        old?.endAudio()
    }

    /// Called on the main thread.
    func setEnabled(_ on: Bool) {
        guard on != wanted else { return }
        wanted = on
        enableGeneration += 1
        if on { authorizeThenStart() } else { stopListening(); state = .off }
    }

    // MARK: Permissions

    private func authorizeThenStart() {
        let generation = enableGeneration
        requestMicrophone { [weak self] micGranted in
            guard let self, self.wanted, self.enableGeneration == generation else { return }
            guard micGranted else { self.state = .denied(.microphone); return }
            self.requestSpeech { speechGranted in
                guard self.wanted, self.enableGeneration == generation else { return }
                guard speechGranted else { self.state = .denied(.speech); return }
                self.startListening()
            }
        }
    }

    private func requestMicrophone(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: done(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { granted in DispatchQueue.main.async { done(granted) } }
        default: done(false)
        }
    }

    private func requestSpeech(_ done: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: done(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in DispatchQueue.main.async { done(status == .authorized) } }
        default: done(false)
        }
    }

    // MARK: Listening

    private func startListening() {
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("Speech recognition isn't available right now. Try again in a moment.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            state = .unavailable("This Mac can't recognise speech offline yet. Turn on Dictation in System Settings › Keyboard so macOS downloads English speech, then turn this off and on.")
            return
        }
        guard let microphone = MicrophonePicker.preferredInput() else {
            state = .unavailable("Voice commands need your Mac's own microphone or a wired one. Telekin never uses the AirPods mic: it would switch off head tracking.")
            return
        }
        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        do {
            let input = try AVCaptureDeviceInput(device: microphone)
            guard session.canAddInput(input), session.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
            session.addInput(input)
            session.addOutput(output)
        } catch {
            state = .unavailable("Couldn't open \(microphone.localizedName): \(error.localizedDescription)")
            return
        }
        output.setSampleBufferDelegate(self, queue: audioQueue)
        startTask(with: recognizer)
        self.session = session
        audioQueue.async { session.startRunning() }
        observeDeviceChanges()
        renewTimer?.invalidate()
        renewTimer = Timer.scheduledTimer(withTimeInterval: Self.taskLifetime, repeats: true) { [weak self] _ in
            guard let self, VoiceCommandParser.isEmpty(self.utterance), let recognizer = self.recognizer else { return }
            self.startTask(with: recognizer)
        }
        state = .listening
    }

    private func startTask(with recognizer: SFSpeechRecognizer) {
        task?.cancel()
        settleTimer?.invalidate()
        let next = SFSpeechAudioBufferRecognitionRequest()
        next.requiresOnDeviceRecognition = true
        next.shouldReportPartialResults = true
        next.addsPunctuation = false
        next.contextualStrings = VoiceCommand.allPhrases
        swapRequest(next)
        utterance = ""
        taskStarted = Date()
        generation += 1
        let current = generation
        task = recognizer.recognitionTask(with: next) { [weak self] result, error in
            DispatchQueue.main.async { self?.handle(result: result, error: error, generation: current) }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, generation current: Int) {
        guard wanted, current == generation, state == .listening else { return }
        if let result {
            utterance = result.bestTranscription.formattedString
            failures = 0
            settleTimer?.invalidate()
            if result.isFinal {
                settle()
            } else {
                settleTimer = Timer.scheduledTimer(withTimeInterval: Self.utterancePause, repeats: false) { [weak self] _ in self?.settle() }
            }
        }
        guard let error else { return }
        let nsError = error as NSError
        Self.log.notice("task ended: \(nsError.domain, privacy: .public) \(nsError.code) \(nsError.localizedDescription, privacy: .public)")
        if !VoiceCommandParser.isEmpty(utterance) { settle(); return }
        // The task ended without words (a hiccup or the time limit): start a fresh one, backing off if it keeps failing.
        failures = Date().timeIntervalSince(taskStarted) < Self.quickFailure ? failures + 1 : 0
        guard failures < Self.maxFailures else {
            stopListening()
            state = .unavailable("Speech recognition stopped working (\(error.localizedDescription)). Turn voice commands off and on to retry.")
            return
        }
        generation += 1
        let waited = generation
        let delay = min(Self.maxRetryDelay, Self.retryDelay * pow(2, Double(failures)))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.wanted, self.generation == waited, self.state == .listening, let recognizer = self.recognizer else { return }
            self.startTask(with: recognizer)
        }
    }

    /// You paused: act on the utterance if it was only commands, then listen afresh for the next one.
    private func settle() {
        settleTimer?.invalidate()
        let heard = utterance
        Self.log.notice("utterance of \(VoiceCommandParser.words(in: heard).count) words -> \(VoiceCommandParser.commands(inUtterance: heard).map(\.phrase), privacy: .public)")
        if let recognizer { startTask(with: recognizer) }
        for command in VoiceCommandParser.commands(inUtterance: heard) { onCommand?(command) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        requestLock.withLock { request?.appendAudioSampleBuffer(sampleBuffer) }
    }

    /// A microphone appearing or disappearing (or the session failing) may change the best choice: start again.
    private func observeDeviceChanges() {
        guard deviceObservers.isEmpty else { return }
        let restart: (Notification) -> Void = { [weak self] _ in
            guard let self, self.wanted else { return }
            self.stopListening()
            self.startListening()
        }
        let center = NotificationCenter.default
        deviceObservers = [
            center.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main, using: restart),
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main, using: restart),
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: nil, queue: .main, using: restart),
        ]
    }

    private func stopListening() {
        renewTimer?.invalidate()
        renewTimer = nil
        deviceObservers.forEach(NotificationCenter.default.removeObserver)
        deviceObservers = []
        if let session {
            audioQueue.async { session.stopRunning() }
        }
        session = nil
        settleTimer?.invalidate()
        swapRequest(nil)
        task?.cancel()
        task = nil
        generation += 1
    }
}
