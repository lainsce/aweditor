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
    /// Music is split by purpose so map-authoring ambience cannot collide with
    /// the army/ruleset tracks used by playtest. The folder is preserved in
    /// the app bundle by the BGM folder reference in the Xcode project.
    enum Library: String, Sendable {
        case design = "BGM/Design"
        case play = "BGM/Play"
    }

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioBuffer: AVAudioPCMBuffer?
    private var bufferIsScheduled = false
    private var resourceKey: String?

    func apply(tileset: Tileset, enabled: Bool, volume: Int) {
        apply(
            resourceName: tileset.backgroundMusicResourceName,
            library: .design,
            enabled: enabled,
            volume: volume
        )
    }

    /// Applies the army-specific playtest track. Files are resolved from the
    /// Play library only; when a set has not yet supplied a track, the
    /// controller stops cleanly instead of leaving the previous army's music
    /// playing through the turn transition.
    func apply(
        playtestTileset tileset: Tileset,
        army: Int,
        cue: PlaytestMusicCue = .neutral,
        enabled: Bool,
        volume: Int
    ) {
        apply(
            resourceNames: PlaytestMusicRouter.resourceNameCandidates(
                tileset: tileset,
                army: army,
                cue: cue
            ),
            library: .play,
            enabled: enabled,
            volume: volume
        )
    }

    /// Tries a list in order so compact legacy filenames and readable new
    /// filenames can coexist in the same Play folder.
    func apply(
        resourceNames: [String],
        library: Library,
        enabled: Bool,
        volume: Int
    ) {
        guard enabled else {
            stop()
            return
        }
        guard let resourceName = resourceNames.first(where: {
            resourceURL(for: $0, library: library) != nil
        }) else {
            resetPlayer()
            return
        }
        apply(
            resourceName: resourceName,
            library: library,
            enabled: true,
            volume: volume
        )
    }

    /// Applies a playtest cue from the separate Play library. Keeping this
    /// generic lets the ruleset map one army to several cues (for example
    /// GB Wars 3 winning/neutral/losing) without changing the audio loader.
    func apply(
        resourceName: String,
        library: Library,
        enabled: Bool,
        volume: Int
    ) {
        let nextResourceKey = "\(library.rawValue)/\(resourceName)"
        if resourceKey != nextResourceKey {
            stop()
            engine = nil
            playerNode = nil
            audioBuffer = nil
            resourceKey = nextResourceKey
        }

        guard enabled else {
            stop()
            return
        }
        guard let playerNode = ensurePlayer(for: resourceName, library: library) else { return }

        playerNode.volume = Float(min(max(volume, 0), 100)) / 100
        startPlayback()
    }

    private func resetPlayer() {
        stop()
        engine = nil
        playerNode = nil
        audioBuffer = nil
        resourceKey = nil
    }

    func stop() {
        playerNode?.stop()
        engine?.stop()
        bufferIsScheduled = false
    }

    private func ensurePlayer(for resourceName: String, library: Library) -> AVAudioPlayerNode? {
        if let playerNode { return playerNode }

        guard let url = resourceURL(for: resourceName, library: library),
              let file = try? AVAudioFile(forReading: url),
              file.length > 0,
              file.length <= Int64(UInt32.max),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
              ) else { return nil }

        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        guard connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat, using: engine) else {
            return nil
        }
        engine.prepare()

        self.engine = engine
        self.playerNode = playerNode
        audioBuffer = library == .play ? trimLeadingSilence(from: buffer) : buffer
        return playerNode
    }

    /// MP3 encoders commonly leave a short silent lead-in (and some of the
    /// extracted game tracks have a longer authored lead-in). Keep the source
    /// files untouched, but remove that silence from playtest buffers before
    /// scheduling them so army music starts immediately and loops cleanly.
    private func trimLeadingSilence(from buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard buffer.frameLength > 0,
              let sourceChannels = buffer.floatChannelData else { return buffer }

        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate
        let analysisFrames = max(1, Int(sampleRate * 0.01))
        let silenceThreshold: Float = 0.001
        var leadingFrames: AVAudioFrameCount = 0

        while leadingFrames < buffer.frameLength {
            let remaining = Int(buffer.frameLength - leadingFrames)
            let frameCount = min(analysisFrames, remaining)
            var peak: Float = 0

            for channel in 0..<channelCount {
                let samples = sourceChannels[channel].advanced(by: Int(leadingFrames))
                for frame in 0..<frameCount {
                    peak = max(peak, abs(samples[frame]))
                }
            }

            guard peak < silenceThreshold else { break }
            leadingFrames += AVAudioFrameCount(frameCount)
        }

        guard leadingFrames > 0,
              leadingFrames < buffer.frameLength,
              let trimmed = AVAudioPCMBuffer(
                  pcmFormat: buffer.format,
                  frameCapacity: buffer.frameLength - leadingFrames
              ),
              let destinationChannels = trimmed.floatChannelData else {
            return buffer
        }

        let remainingFrames = buffer.frameLength - leadingFrames
        trimmed.frameLength = remainingFrames
        for channel in 0..<channelCount {
            destinationChannels[channel].update(
                from: sourceChannels[channel].advanced(by: Int(leadingFrames)),
                count: Int(remainingFrames)
            )
        }
        return trimmed
    }

    private func resourceURL(for resourceName: String, library: Library) -> URL? {
        let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(library.rawValue)
            .appendingPathComponent("\(resourceName).mp3")
        let bundledURL = Bundle.main.url(
            forResource: resourceName,
            withExtension: "mp3",
            subdirectory: library.rawValue
        )
        // Keep old development builds usable while the folder layout settles,
        // but prefer the explicit library path whenever it exists.
        let legacyURL = Bundle.main.url(forResource: resourceName, withExtension: "mp3")
        return [resourceURL, bundledURL, legacyURL]
            .compactMap { $0 }
            .first { url in
                guard FileManager.default.fileExists(atPath: url.path),
                      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let size = attributes[.size] as? NSNumber else { return false }
                return size.int64Value > 0
            }
    }

    private func startPlayback() {
        guard let engine,
              let playerNode,
              let audioBuffer else { return }

        if !bufferIsScheduled {
            playerNode.scheduleBuffer(audioBuffer, at: nil, options: .loops)
            bufferIsScheduled = true
        }

        guard !engine.isRunning else {
            if !playerNode.isPlaying { _ = play(playerNode) }
            return
        }

        do {
            try engine.start()
            guard play(playerNode) else { throw PlaybackError.couldNotStart }
        } catch {
            bufferIsScheduled = false
            playerNode.stop()
            engine.stop()
        }
    }

    private func connect(
        _ playerNode: AVAudioPlayerNode,
        to mixer: AVAudioMixerNode,
        format: AVAudioFormat,
        using engine: AVAudioEngine
    ) -> Bool {
        if #available(macOS 27, *) {
            do {
                try engine.connectNode(playerNode, to: mixer, format: format)
                return true
            } catch {
                return false
            }
        } else {
            engine.connect(playerNode, to: mixer, format: format)
            return true
        }
    }

    private func play(_ playerNode: AVAudioPlayerNode) -> Bool {
        if #available(macOS 27, *) {
            do {
                try playerNode.playAudio()
                return true
            } catch {
                return false
            }
        } else {
            playerNode.play()
            return true
        }
    }

    private enum PlaybackError: Error {
        case couldNotStart
    }
}
