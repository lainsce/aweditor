import AppKit
import SwiftUI
import AWEDCore

enum AWCursorKind: Hashable {
    case allowed
    case forbidden
    case delete
}

enum AWCursorFrame: Hashable {
    case single
    case large3
    case large4
}

/// The original misc sprite sheet contains both the tile-sized AW cursor
/// frames and the small allowed/forbidden/delete pointer glyphs.
@MainActor
final class CursorAtlas {
    static let shared = CursorAtlas()

    private var sheets: [String: CGImage] = [:]
    private var images: [String: Image] = [:]
    private var cursors: [String: NSCursor] = [:]

    func frameImage(_ frame: AWCursorFrame, tileset: Tileset) -> Image? {
        let key = "frame-\(frame)-\(sheetName(for: tileset))"
        if let image = images[key] { return image }
        let rect: CGRect
        switch frame {
        case .single: rect = CGRect(x: 0, y: 16, width: 18, height: 18)
        case .large3: rect = CGRect(x: 18, y: 16, width: 48, height: 48)
        case .large4: rect = CGRect(x: 0, y: 64, width: 64, height: 64)
        }
        guard let cropped = crop(rect, from: sheetName(for: tileset)) else { return nil }
        let image = Image(decorative: cropped, scale: 1, orientation: .up)
        images[key] = image
        return image
    }

    func cursor(_ kind: AWCursorKind, tileset: Tileset) -> NSCursor? {
        let key = "pointer-\(kind)-\(sheetName(for: tileset))"
        if let cursor = cursors[key] { return cursor }
        let rect: CGRect
        switch kind {
        case .allowed:
            rect = CGRect(x: 0, y: 0, width: 16, height: 16)
        case .forbidden:
            rect = CGRect(x: 16, y: 0, width: 16, height: 16)
        case .delete:
            rect = CGRect(x: 48, y: 0, width: 32, height: 16)
        }
        guard let cropped = crop(rect, from: sheetName(for: tileset)) else { return nil }
        let image = NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
        // The original editor blits this pointer at the raw mouse origin;
        // its down-right tip then occupies the open fourth-ball position.
        // AppKit's flipped cursor coordinates also use the top-left corner
        // as the origin, so a zero hotspot preserves that sprite placement.
        let hotSpot = NSPoint.zero
        let cursor = NSCursor(image: image, hotSpot: hotSpot)
        cursors[key] = cursor
        return cursor
    }

    private func sheetName(for tileset: Tileset) -> String {
        switch tileset {
        case .normal, .snow, .desert, .wasteland, .famicomWars, .gbWars,
             .superFamicomWars, .daysOfRuin, .gbWars2, .gbWars3: "misc_0"
        case .aw1: "misc_4"
        case .aw2: "misc_5"
        }
    }

    private func crop(_ rect: CGRect, from sheetName: String) -> CGImage? {
        guard let sheet = loadSheet(named: sheetName),
              rect.minX >= 0, rect.minY >= 0,
              rect.maxX <= CGFloat(sheet.width), rect.maxY <= CGFloat(sheet.height) else { return nil }
        return sheet.cropping(to: rect)
    }

    private func loadSheet(named name: String) -> CGImage? {
        if let sheet = sheets[name] { return sheet }
        // Xcode may retain the `Spritesheets` directory or flatten resource
        // files into the application bundle. Accept both layouts so the
        // original AW cursor artwork is always used instead of silently
        // falling back to the outline cursor.
        let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Spritesheets")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        guard let url,
              let image = NSImage(contentsOf: url) else { return nil }
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        sheets[name] = cgImage
        return cgImage
    }
}

@MainActor
final class AWCursorController {
    static let shared = AWCursorController()

    private var currentKey: String?

    func update(kind: AWCursorKind, tileset: Tileset) {
        let key = "\(kind)-\(tileset.rawValue)"
        guard key != currentKey else { return }
        currentKey = key
        if let cursor = CursorAtlas.shared.cursor(kind, tileset: tileset) {
            cursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    func reset() {
        guard currentKey != nil else { return }
        currentKey = nil
        NSCursor.arrow.set()
    }
}
