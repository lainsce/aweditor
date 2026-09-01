import AppKit
import SwiftUI
import AWEDCore


struct PlaytestMapColumn: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let atlas: SpriteAtlas
    let mapSize: CGSize

    var body: some View {
        PlaytestMapSurface(
            session: session,
            previewModel: previewModel,
            atlas: atlas,
            mapSize: mapSize
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
