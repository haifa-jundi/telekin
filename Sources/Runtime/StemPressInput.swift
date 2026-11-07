import Foundation
import MediaPlayer

/// Experimental: turns AirPods stem presses into clicks.
///
/// The head-motion API does not report presses, but AirPods send them to the Mac as media
/// commands (press once = play/pause, twice = next track). While enabled, Telekin claims
/// "Now Playing" (it already plays its quiet spatial tone) so those commands come here.
/// Side effect: while it holds Now Playing, presses no longer pause other apps' music.
final class StemPressInput {
    /// Return true if the press was used; false lets the system pass the command on (e.g. to a music app).
    var onSinglePress: (() -> Bool)?
    var onDoublePress: (() -> Bool)?
    private(set) var isEnabled = false

    private let center = MPRemoteCommandCenter.shared()
    private var targets: [(MPRemoteCommand, Any)] = []

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        enabled ? claim() : release()
    }

    private func claim() {
        let single: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] _ in
            Self.onMain { self?.onSinglePress?() ?? false } ? .success : .noActionableNowPlayingItem
        }
        let double: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] _ in
            Self.onMain { self?.onDoublePress?() ?? false } ? .success : .noActionableNowPlayingItem
        }
        for command in [center.togglePlayPauseCommand, center.playCommand, center.pauseCommand] {
            command.isEnabled = true
            targets.append((command, command.addTarget(handler: single)))
        }
        center.nextTrackCommand.isEnabled = true
        targets.append((center.nextTrackCommand, center.nextTrackCommand.addTarget(handler: double)))

        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = [MPMediaItemPropertyTitle: "Telekin", MPMediaItemPropertyArtist: "AirPods presses click"]
        info.playbackState = .playing
    }

    /// Remote commands may arrive off the main thread; clicks and UI work must run on it.
    private static func onMain(_ work: () -> Bool) -> Bool {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    private func release() {
        for (command, target) in targets { command.removeTarget(target) }
        targets.removeAll()
        let info = MPNowPlayingInfoCenter.default()
        info.playbackState = .stopped
        info.nowPlayingInfo = nil
    }
}
