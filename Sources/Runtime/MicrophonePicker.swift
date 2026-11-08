import AVFoundation
import CoreAudio

/// Chooses the microphone for voice commands. Never a Bluetooth one: opening the AirPods mic switches them
/// to hands-free (call) mode, which turns off spatial audio and with it the head tracking Telekin steers by.
enum MicrophonePicker {
    /// The default input if it is not Bluetooth, else the built-in mic, else any other non-Bluetooth input.
    static func preferredInput() -> AVCaptureDevice? {
        let candidates = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
            .devices.filter { !isBluetooth($0) }
        if let current = AVCaptureDevice.default(for: .audio), candidates.contains(current) { return current }
        return candidates.first { UInt32(bitPattern: $0.transportType) == kAudioDeviceTransportTypeBuiltIn } ?? candidates.first
    }

    private static func isBluetooth(_ device: AVCaptureDevice) -> Bool {
        let kind = UInt32(bitPattern: device.transportType)
        return kind == kAudioDeviceTransportTypeBluetooth || kind == kAudioDeviceTransportTypeBluetoothLE
    }
}
