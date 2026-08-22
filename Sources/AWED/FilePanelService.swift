import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AWEDCore

@MainActor
enum FilePanelService {
    static func openMap() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Map"
        panel.allowedContentTypes = Self.contentTypes(for: ["awm", "aw2", "awd", "aws"])
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func saveMap(defaultURL: URL?) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Map"
        panel.allowedContentTypes = Self.contentTypes(for: ["aws", "awm", "aw2", "awd"])
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultURL?.lastPathComponent ?? "Untitled.aws"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.pathExtension.isEmpty ? url.appendingPathExtension("aws") : url
    }

    static func saveScreenshot(defaultURL: URL?) -> ScreenshotRequest? {
        let panel = NSSavePanel()
        panel.title = "Save Screenshot"
        panel.allowedContentTypes = Self.contentTypes(for: ["png", "jpg", "jpeg", "bmp", "xpm", "ico"])
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultURL?.deletingPathExtension().appendingPathExtension("png").lastPathComponent ?? "Map Screenshot.png"
        let sizePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 24), pullsDown: false)
        sizePopup.addItems(withTitles: ScreenshotSize.allCases.map(\.displayName))
        let sizeLabel = NSTextField(labelWithString: "Image size:")
        sizeLabel.alignment = .right
        let accessory = NSStackView(views: [sizeLabel, sizePopup])
        accessory.orientation = .horizontal
        accessory.spacing = 8
        accessory.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        accessory.frame = NSRect(x: 0, y: 0, width: 300, height: 32)
        panel.accessoryView = accessory
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return ScreenshotRequest(url: url.pathExtension.isEmpty ? url.appendingPathExtension("png") : url,
                                 size: ScreenshotSize.allCases[sizePopup.indexOfSelectedItem])
    }

    private static func contentTypes(for extensions: [String]) -> [UTType] {
        extensions.compactMap { UTType(filenameExtension: $0) }
    }
}

struct ScreenshotRequest {
    let url: URL
    let size: ScreenshotSize
}

enum ScreenshotSize: CaseIterable {
    case full
    case half
    case miniature

    var displayName: String {
        switch self {
        case .full: "Full size"
        case .half: "Half size"
        case .miniature: "Icon miniature"
        }
    }
}

@MainActor
enum ScreenshotRenderer {
    static func render(
        map: MapState,
        atlas: SpriteAtlas,
        scale: Int = 1,
        palette: SpritePalette? = nil
    ) -> NSImage {
        let palette = palette ?? .tileset(map.tileset)
        let tile = 16 * max(1, scale)
        let canvasHeight = CGFloat(map.height * tile)
        let staggered = MapCanvasMetrics.isStaggeredGB(map: map, palette: palette)
        let canvasWidth = CGFloat(map.width * tile) + (staggered && map.height > 1 ? CGFloat(tile) / 2 : 0)
        let image = NSImage(size: NSSize(width: canvasWidth, height: canvasHeight))
        // AppKit's image drawing APIs expect CGImage content in a bottom-left
        // coordinate system. Keep the exported pixels upright by drawing into
        // an unflipped context and converting each map cell from its top-left
        // map coordinate to the corresponding bottom-left rectangle.
        image.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)).fill()
        for x in 0..<map.width {
            for y in 0..<map.height {
                let rowOffset = staggered && y % 2 != 0 ? CGFloat(tile) / 2 : 0
                let topRect = NSRect(x: CGFloat(x * tile) + rowOffset, y: CGFloat(y * tile), width: CGFloat(tile), height: CGFloat(tile))
                let rect = NSRect(x: topRect.minX,
                                  y: canvasHeight - topRect.maxY,
                                  width: topRect.width,
                                  height: topRect.height)
                draw(map.backgroundDrawElement(atX: x, y: y), in: rect, map: map, atlas: atlas, palette: palette)
                drawSeaCoast(atX: x, y: y, in: rect, map: map, atlas: atlas, palette: palette)
                draw(map.foregroundElement(atX: x, y: y), in: rect, map: map, atlas: atlas, palette: palette)
            }
        }
        image.unlockFocus()
        return image
    }

    static func write(_ image: NSImage, to url: URL) throws {
        let extensionName = url.pathExtension.lowercased()
        if extensionName == "xpm" {
            try writeXPM(image, to: url)
            return
        }
        if extensionName == "ico" {
            try writeICO(image, to: url)
            return
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { throw MapFileError.cannotWrite }
        let type: NSBitmapImageRep.FileType = ["jpg", "jpeg"].contains(extensionName) ? .jpeg : ["bmp"].contains(extensionName) ? .bmp : .png
        guard let data = bitmap.representation(using: type, properties: [:]) else { throw MapFileError.cannotWrite }
        try data.write(to: url, options: .atomic)
    }

    static func apply(_ size: ScreenshotSize, to image: NSImage) -> NSImage {
        let factor: CGFloat
        let maximum: CGSize?
        switch size {
        case .full:
            factor = 1
            maximum = nil
        case .half:
            factor = 0.5
            maximum = nil
        case .miniature:
            factor = 1
            maximum = CGSize(width: 255, height: 127)
        }
        let original = image.size
        let target: NSSize
        if let maximum {
            let fit = min(maximum.width / original.width, maximum.height / original.height, 1)
            target = NSSize(width: max(1, floor(original.width * fit)), height: max(1, floor(original.height * fit)))
        } else {
            target = NSSize(width: max(1, floor(original.width * factor)), height: max(1, floor(original.height * factor)))
        }
        guard target != original else { return image }
        let resized = NSImage(size: target)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target), from: NSRect(origin: .zero, size: original), operation: .copy, fraction: 1)
        resized.unlockFocus()
        return resized
    }

    private static func writeICO(_ image: NSImage, to url: URL) throws {
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.ico.identifier as CFString, 1, nil) else {
            throw MapFileError.cannotWrite
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw MapFileError.cannotWrite }
    }

    private static func writeXPM(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pixels = bitmap.bitmapData else { throw MapFileError.cannotWrite }
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let components = max(1, bitmap.samplesPerPixel)
        let alphaInfo = bitmap.hasAlpha ? 1 : 0
        let alphabet = Array("!#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~")
        let colorCount = width * height
        let charsPerPixel = colorCount > alphabet.count * alphabet.count ? 3 : colorCount > alphabet.count ? 2 : 1
        let symbolCount = Int(pow(Double(alphabet.count), Double(charsPerPixel)))

        func symbol(for index: Int) -> String {
            var value = index
            var result = ""
            for _ in 0..<charsPerPixel {
                result.append(alphabet[value % alphabet.count])
                value /= alphabet.count
            }
            return result
        }

        func color(at x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let offset = y * bitmap.bytesPerRow + x * components
            if bitmap.bitmapFormat.contains(.alphaFirst) {
                let a = alphaInfo == 1 ? pixels[offset] : 255
                return (pixels[offset + (alphaInfo == 1 ? 1 : 0)], pixels[offset + (alphaInfo == 1 ? 2 : 1)], pixels[offset + (alphaInfo == 1 ? 3 : 2)], a)
            }
            let r = pixels[offset]
            let g = components > 1 ? pixels[offset + 1] : r
            let b = components > 2 ? pixels[offset + 2] : g
            let a = alphaInfo == 1 ? pixels[offset + components - 1] : 255
            return (r, g, b, a)
        }

        var colors: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)] = []
        var indices = [Int](repeating: 0, count: colorCount)
        var lookup: [UInt32: Int] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * width + x
                let value = color(at: x, y: y)
                let key = UInt32(value.r) << 24 | UInt32(value.g) << 16 | UInt32(value.b) << 8 | UInt32(value.a)
                if let existing = lookup[key] {
                    indices[pixelIndex] = existing
                } else {
                    let next = colors.count
                    guard next < symbolCount else { throw MapFileError.cannotWrite }
                    lookup[key] = next
                    colors.append(value)
                    indices[pixelIndex] = next
                }
            }
        }

        var output = "/* XPM */\nstatic char * image[] = {\n"
        output += "\"\(width) \(height) \(colors.count) \(charsPerPixel)\",\n"
        for (index, color) in colors.enumerated() {
            let value = color.a < 128 ? "None" : String(format: "#%02X%02X%02X", color.r, color.g, color.b)
            output += "\"\(symbol(for: index)) c \(value)\",\n"
        }
        for y in 0..<height {
            let row = (0..<width).map { symbol(for: indices[y * width + $0]) }.joined()
            output += "\"\(row)\"\(y == height - 1 ? "" : ",")\n"
        }
        output += "};\n"
        guard let data = output.data(using: .utf8) else { throw MapFileError.cannotWrite }
        try data.write(to: url, options: .atomic)
    }

    private static func draw(
        _ element: Element,
        in rect: NSRect,
        map: MapState,
        atlas: SpriteAtlas,
        palette: SpritePalette
    ) {
        guard let cgImage = atlas.cgImage(for: element, palette: palette) else { return }
        let isDoubleHeight = palette.doubleHeight(for: element)
        let target = isDoubleHeight ? NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 2) : rect
        let image = NSImage(cgImage: cgImage, size: NSSize(width: target.width, height: target.height))
        // Staggering changes each cell's origin, not its four-sided shape.
        // Double-height sprites intentionally remain unclipped so they can
        // project above their anchor cell.
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private static func drawSeaCoast(atX x: Int, y: Int, in rect: NSRect, map: MapState, atlas: SpriteAtlas, palette: SpritePalette) {
        guard map.tileset != .gbWars, map.backgroundDrawElement(atX: x, y: y) == .terrainSea else { return }
        let up = map.backgroundElement(atX: x, y: y - 1)
        let down = map.backgroundElement(atX: x, y: y + 1)
        let left = map.backgroundElement(atX: x - 1, y: y)
        let right = map.backgroundElement(atX: x + 1, y: y)
        let upLeft = map.backgroundElement(atX: x - 1, y: y - 1)
        let upRight = map.backgroundElement(atX: x + 1, y: y - 1)
        let downRight = map.backgroundElement(atX: x + 1, y: y + 1)
        let downLeft = map.backgroundElement(atX: x - 1, y: y + 1)
        let overlays: [(Element, Bool)] = [
            (Element(AWConstants.makeTerrain(6, 3)), upLeft.isLand && !up.isLand && !left.isLand),
            (Element(AWConstants.makeTerrain(5, 3)), upRight.isLand && !up.isLand && !right.isLand),
            (Element(AWConstants.makeTerrain(5, 2)), downRight.isLand && !down.isLand && !right.isLand),
            (Element(AWConstants.makeTerrain(6, 2)), downLeft.isLand && !down.isLand && !left.isLand),
            (Element(AWConstants.makeTerrain(5, 4)), left.isLand),
            (Element(AWConstants.makeTerrain(5, 5)), up.isLand),
            (Element(AWConstants.makeTerrain(6, 4)), right.isLand),
            (Element(AWConstants.makeTerrain(6, 5)), down.isLand),
            (Element(AWConstants.makeTerrain(5, 0)), up.isLand && left.isLand),
            (Element(AWConstants.makeTerrain(6, 0)), up.isLand && right.isLand),
            (Element(AWConstants.makeTerrain(5, 1)), down.isLand && left.isLand),
            (Element(AWConstants.makeTerrain(6, 1)), down.isLand && right.isLand)
        ]
        for (element, shouldDraw) in overlays where shouldDraw {
            draw(element, in: rect, map: map, atlas: atlas, palette: palette)
        }
    }
}
