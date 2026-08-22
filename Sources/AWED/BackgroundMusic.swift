import AVFoundation
import Foundation
import AWEDCore

/// Owns the editor's optional looping background track.
///
/// The original editor looked for a track beside the application and applied
/// the saved enable/volume settings as soon as the media loaded. The Xcode
/// target copies the tileset-specific tracks into the application bundle so
/// the app remains self-contained.
@MainActor
final class BackgroundMusicController {
    private var player: AVAudioPlayer?
    private var resourceName: String?

    func apply(tileset: Tileset, enabled: Bool, volume: Int) {
        let nextResourceName = tileset.backgroundMusicResourceName
        if resourceName != nextResourceName {
            player?.stop()
            player = nil
            resourceName = nextResourceName
        }

        guard enabled else {
            player?.stop()
            return
        }
        guard let player = ensurePlayer(for: nextResourceName) else { return }

        player.volume = Float(min(max(volume, 0), 100)) / 100
        if !player.isPlaying { player.play() }
    }

    func stop() {
        player?.stop()
    }

    private func ensurePlayer(for resourceName: String) -> AVAudioPlayer? {
        if let player { return player }
        let adjacentURL = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appending(path: "\(resourceName).mp3")
        let url = adjacentURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? Bundle.main.url(forResource: resourceName, withExtension: "mp3")
        guard let url,
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = -1
        player.prepareToPlay()
        self.player = player
        return player
    }
}
