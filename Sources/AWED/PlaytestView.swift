import SwiftUI
import AWEDCore

struct PlaytestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: PlaytestSession
    @State private var previewModel: EditorModel
    @State private var dayBannerSequence = 0
    @State private var isDayBannerVisible = false

    let atlas: SpriteAtlas
    let mapSize: CGSize

    init(map: MapState, visualVariant: MapVisualVariant? = nil, atlas: SpriteAtlas) {
        let session = PlaytestSession(map: map, visualVariant: visualVariant)
        _session = State(initialValue: session)
        let previewModel = EditorModel(map: session.displayMap)
        previewModel.spritePalette = session.displayPalette
        _previewModel = State(initialValue: previewModel)
        self.atlas = atlas
        self.mapSize = MapCanvasMetrics.mapPixelSize(
            width: map.width,
            height: map.height,
            tileSize: MapCanvasMetrics.tileSize,
            staggered: session.isStaggeredGrid
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            PlaytestHeader(
                session: session,
                restartAction: session.restart,
                endTurnAction: session.endTurn,
                exitAction: {
                    session.stopCPU()
                    dismiss()
                }
            )
            Divider()
            HStack(spacing: 0) {
                PlaytestMapColumn(
                    session: session,
                    previewModel: previewModel,
                    atlas: atlas,
                    mapSize: mapSize,
                    showDayBanner: isDayBannerVisible,
                    dayBannerSequence: dayBannerSequence
                )
                Divider()
                PlaytestInspector(session: session)
                    .frame(width: 270)
                    // A playtest is presented as a sheet. Use the same
                    // sidebar material, but blend within that sheet so menu
                    // flyouts do not try to sample through the parent window.
                    .background(GLWNSidebarSurface(blendingMode: .withinWindow))
            }
        }
        .frame(minWidth: 1_080, minHeight: 680)
        .onAppear {
            syncPreviewModel()
            presentDayBanner()
        }
        .task(id: dayBannerSequence) {
            guard dayBannerSequence > 0 else { return }
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isDayBannerVisible = false
            }
        }
        .onChange(of: session.mapRevision) { _, _ in syncPreviewModel() }
        .onChange(of: session.activeArmy) { _, _ in
            // The backdrop only changes with the active army when Fog of War
            // (or submerged enemy rendering) is involved. Avoid rebuilding
            // the entire sprite Canvas on every ordinary CPU turn switch.
            if session.isFogOfWarActive || !session.submergedUnits.isEmpty {
                syncPreviewModel()
            }
            presentDayBanner()
        }
        .onChange(of: session.fogOfWarEnabled) { _, _ in syncPreviewModel() }
        .onChange(of: session.weather) { _, _ in syncPreviewModel() }
        .onChange(of: session.submergedRevision) { _, _ in syncPreviewModel() }
    }

    private func syncPreviewModel() {
        previewModel.map = session.displayMap
        previewModel.spritePalette = session.displayPalette
    }

    private func presentDayBanner() {
        withAnimation(.easeOut(duration: 0.16)) {
            dayBannerSequence &+= 1
            isDayBannerVisible = true
        }
    }
}
