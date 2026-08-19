import AVFoundation
import Foundation

/// Owns the editor's optional looping background track.
///
/// The original editor looked for `bgm.mp3` beside the application and
/// applied the saved enable/volume settings as soon as the media loaded. The
/// Xcode target copies the same track into the application bundle so the app
/// remains self-contained.
@MainActor
final class BackgroundMusicController {
    private var player: AVAudioPlayer?

    func apply(enabled: Bool, volume: Int) {
        guard enabled || player != nil else { return }
        guard let player = ensurePlayer() else { return }

        player.volume = Float(min(max(volume, 0), 100)) / 100
        if enabled {
            if !player.isPlaying { player.play() }
        } else {
            player.stop()
        }
    }

    func stop() {
        player?.stop()
    }

    private func ensurePlayer() -> AVAudioPlayer? {
        if let player { return player }
        let adjacentURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("bgm.mp3")
        let url = adjacentURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? Bundle.main.url(forResource: "bgm", withExtension: "mp3")
        guard let url,
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = -1
        player.prepareToPlay()
        self.player = player
        return player
    }
}
