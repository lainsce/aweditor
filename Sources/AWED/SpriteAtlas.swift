import AppKit
import SwiftUI
import AWEDCore

@MainActor
final class SpriteAtlas {
    private var sheets: [String: CGImage] = [:]
    private var sprites: [String: Image] = [:]

    func image(for element: Element, tileset: Tileset) -> Image? {
        guard element.drawable else { return nil }
        let sheetName = "\(element.spritesheet.rawValue)_\(tileset.rawValue)"
        let cacheKey = "\(sheetName)-\(element.value)"
        if let cached = sprites[cacheKey] { return cached }
        guard let cropped = croppedImage(for: element, sheetName: sheetName) else { return nil }
        let image = Image(decorative: cropped, scale: 1, orientation: .up)
        sprites[cacheKey] = image
        return image
    }

    func cgImage(for element: Element, tileset: Tileset) -> CGImage? {
        guard element.drawable else { return nil }
        let sheetName = "\(element.spritesheet.rawValue)_\(tileset.rawValue)"
        return croppedImage(for: element, sheetName: sheetName)
    }

    private func croppedImage(for element: Element, sheetName: String) -> CGImage? {
        guard let sheet = loadSheet(named: sheetName) else { return nil }
        let sourceWidth = 16
        let sourceHeight = element.doubleHeight ? 32 : 16
        let sourceX = element.drawX * 16
        let sourceYFromTop = element.drawY * 16
        guard sourceX >= 0, sourceYFromTop >= 0, sourceX + sourceWidth <= sheet.width, sourceYFromTop + sourceHeight <= sheet.height else { return nil }
        let sourceRect = CGRect(
            x: sourceX,
            // CGImage cropping uses the image's top-left pixel origin. The
            // legacy sprite tables are also indexed from the top-left.
            y: sourceYFromTop,
            width: sourceWidth,
            height: sourceHeight
        )
        return sheet.cropping(to: sourceRect)
    }

    private func loadSheet(named name: String) -> CGImage? {
        if let sheet = sheets[name] { return sheet }
        let parts = name.split(separator: "_")
        guard parts.count == 2 else { return nil }
        let resourceName = String(parts[0]) + "_" + String(parts[1])
        // Xcode may retain the `Spritesheets` directory or flatten resource
        // files into the application bundle. Keep both lookups so the atlas
        // remains usable from a normal app bundle.
        let url = Bundle.main.url(forResource: resourceName, withExtension: "png", subdirectory: "Spritesheets")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "png")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        sheets[name] = cgImage
        return cgImage
    }
}
