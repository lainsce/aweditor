import SwiftUI
import AWEDCore

struct ContentView: View {
    @Bindable var model: EditorModel
    let atlas: SpriteAtlas
    let music: BackgroundMusicController

    @State private var pendingWarningURL: URL? = nil
    @State private var pendingWarningMessage = ""
    @State private var isShowingWarning = false

    init(model: EditorModel, atlas: SpriteAtlas = SpriteAtlas(), music: BackgroundMusicController) {
        self.model = model
        self.atlas = atlas
        self.music = music
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                MapWorkspaceView(model: model, atlas: atlas)
                Divider()
                    .ignoresSafeArea(.container)
                VStack(spacing: 0) {
                    PaletteView(model: model, atlas: atlas)
                    StatusBarView(name: model.map.name, author: model.map.author, coordinates: model.statusMessage, isDirty: model.map.isDirty)
                }
                .background(GLWNSidebarSurface())
                .ignoresSafeArea(.all)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle(model.documentTitle)
        .toolbar {
            EditorToolbar(
                model: model,
                newAction: newDocument,
                openAction: openDocument,
                saveAction: saveDocument,
                saveAsAction: saveAsDocument,
                screenshotAction: saveScreenshot
            )
        }
        .sheet(item: $model.dialog) { dialog in
            DialogContainer(dialog: dialog, model: model, music: music)
        }
        .alert("Map compatibility", isPresented: $isShowingWarning) {
            Button("Cancel", role: .cancel) {
                pendingWarningURL = nil
                if model.pendingDocumentAction != nil { model.isShowingUnsavedChanges = true }
            }
            Button("Save Anyway") {
                if let url = pendingWarningURL { writeDocument(to: url) }
                pendingWarningURL = nil
            }
        } message: {
            Text(pendingWarningMessage)
        }
        .alert("AW Map Editor", isPresented: $model.isShowingError) {
            Button("OK") { model.isShowingError = false }
        } message: {
            Text(model.errorMessage ?? "An unknown error occurred.")
        }
        .alert("Unsaved changes", isPresented: $model.isShowingUnsavedChanges) {
            Button("Cancel", role: .cancel) { model.pendingDocumentAction = nil }
            Button("Discard", role: .destructive) { model.discardPendingDocumentAction() }
            Button("Save") { savePendingDocumentAction() }
        } message: {
            Text("Save your changes before continuing?")
        }
    }

    private func newDocument() {
        model.requestNewDocument()
    }

    private func openDocument() {
        guard let url = FilePanelService.openMap() else { return }
        model.requestOpenDocument(url: url)
    }

    private func saveDocument() {
        if let url = model.filename {
            prepareSave(to: url)
        } else {
            saveAsDocument()
        }
    }

    private func saveAsDocument() {
        guard let url = FilePanelService.saveMap(defaultURL: model.filename) else { return }
        prepareSave(to: url)
    }

    private func prepareSave(to url: URL) {
        let format = MapFormat(fileExtension: url.pathExtension)
        let warnings = MapFileCodec.warnings(for: model.map, format: format)
        if warnings.isEmpty {
            writeDocument(to: url)
        } else {
            pendingWarningURL = url
            pendingWarningMessage = warnings.joined(separator: "\n")
            isShowingWarning = true
        }
    }

    private func writeDocument(to url: URL) {
        do {
            _ = try model.save(to: url)
            if model.pendingDocumentAction != nil { model.completePendingDocumentActionAfterSave() }
        } catch { model.presentError(error) }
    }

    private func savePendingDocumentAction() {
        model.isShowingUnsavedChanges = false
        saveDocument()
    }

    private func saveScreenshot() {
        guard let request = FilePanelService.saveScreenshot(defaultURL: model.filename) else { return }
        do {
            let image = ScreenshotRenderer.render(map: model.map, atlas: atlas)
            try ScreenshotRenderer.write(ScreenshotRenderer.apply(request.size, to: image), to: request.url)
        } catch { model.presentError(error) }
    }
}

struct MapWorkspaceView: View {
    let model: EditorModel
    let atlas: SpriteAtlas

    var body: some View {
        GeometryReader { proxy in
            let mapTileSize = MapCanvasMetrics.tileSize
            let mapPixelSize = CGSize(
                width: CGFloat(model.map.width) * mapTileSize,
                height: CGFloat(model.map.height) * mapTileSize
            )
            let boardSize = CGSize(
                width: mapPixelSize.width + (MapCanvasMetrics.woodPadding * 2),
                height: mapPixelSize.height + (MapCanvasMetrics.woodPadding * 2)
            )
            let contentSize = CGSize(
                width: max(proxy.size.width, boardSize.width + (MapCanvasMetrics.parchmentPadding * 2)),
                height: max(proxy.size.height, boardSize.height + (MapCanvasMetrics.parchmentPadding * 2))
            )

            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    MapParchmentSurface(tileSize: mapTileSize, mapSize: mapPixelSize)

                    MapCanvasBoard(model: model, atlas: atlas)
                        .padding(MapCanvasMetrics.parchmentPadding)
                }
                .frame(width: contentSize.width, height: contentSize.height)
            }
            .background {
                MapParchmentSurface(tileSize: mapTileSize, mapSize: mapPixelSize)
                    .ignoresSafeArea(.container, edges: .top)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
