import SwiftUI

extension PlaytestView {
    func routePlaytestMusic() {
        guard let music else { return }
        let cue: PlaytestMusicCue
        if let winner = session.winnerArmy {
            cue = winner == session.activeArmy ? .winning : .losing
        } else {
            cue = session.playtestMusicCue
        }
        music.apply(
            playtestTileset: session.map.tileset,
            army: session.activeArmy,
            cue: cue,
            enabled: designMusicEnabled,
            volume: designMusicVolume
        )
    }

    func restoreEditorMusic() {
        music?.apply(
            tileset: designTileset,
            enabled: designMusicEnabled,
            volume: designMusicVolume
        )
    }

    func exitPlaytest() {
        session.stopCPU()
        restoreEditorMusic()
        dismiss()
    }
}
