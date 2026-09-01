import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AWEDCore

private typealias XPMColor = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

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
        renderTerrain(map: map, atlas: atlas, palette: palette, tile: tile, canvasHeight: canvasHeight, staggered: staggered)
        renderWideProperties(map: map, atlas: atlas, palette: palette, tile: tile, canvasHeight: canvasHeight, staggered: staggered)
        renderForeground(map: map, atlas: atlas, palette: palette, tile: tile, canvasHeight: canvasHeight, staggered: staggered)
        image.unlockFocus()
        return image
    }

    private static func renderTerrain(
        map: MapState,
        atlas: SpriteAtlas,
        palette: SpritePalette,
        tile: Int,
        canvasHeight: CGFloat,
        staggered: Bool
    ) {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let rect = cellRect(atX: x, y: y, tile: tile, canvasHeight: canvasHeight, staggered: staggered)
                if let buildingUnderlay = map.buildingUnderlayDrawElement(atX: x, y: y) {
                    draw(buildingUnderlay, in: rect, map: map, atlas: atlas, palette: palette)
                }
                if let bridgeUnderlay = map.bridgeUnderlayDrawElement(atX: x, y: y) {
                    draw(bridgeUnderlay, in: rect, map: map, atlas: atlas, palette: palette)
                }
                let background = map.backgroundDrawElement(atX: x, y: y)
                if palette.footprint(for: background).width == 1 {
                    draw(background, in: rect, map: map, atlas: atlas, palette: palette)
                    drawSeaCoast(atX: x, y: y, in: rect, map: map, atlas: atlas, palette: palette)
                }
            }
        }
    }

    private static func renderWideProperties(
        map: MapState,
        atlas: SpriteAtlas,
        palette: SpritePalette,
        tile: Int,
        canvasHeight: CGFloat,
        staggered: Bool
    ) {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let rect = cellRect(atX: x, y: y, tile: tile, canvasHeight: canvasHeight, staggered: staggered)
                let background = map.backgroundDrawElement(atX: x, y: y)
                if palette.footprint(for: background).width > 1 {
                    draw(background, in: rect, map: map, atlas: atlas, palette: palette)
                }
            }
        }
    }

    private static func renderForeground(
        map: MapState,
        atlas: SpriteAtlas,
        palette: SpritePalette,
        tile: Int,
        canvasHeight: CGFloat,
        staggered: Bool
    ) {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let rect = cellRect(atX: x, y: y, tile: tile, canvasHeight: canvasHeight, staggered: staggered)
                draw(map.foregroundElement(atX: x, y: y), in: rect, map: map, atlas: atlas, palette: palette)
            }
        }
    }

    private static func cellRect(
        atX x: Int,
        y: Int,
        tile: Int,
        canvasHeight: CGFloat,
        staggered: Bool
    ) -> NSRect {
        let offset = staggered && y % 2 != 0 ? CGFloat(tile) / 2 : 0
        let top = NSRect(x: CGFloat(x * tile) + offset, y: CGFloat(y * tile), width: CGFloat(tile), height: CGFloat(tile))
        return NSRect(x: top.minX, y: canvasHeight - top.maxY, width: top.width, height: top.height)
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
        let alphabet = Array("!#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~")
        let colorCount = width * height
        let charsPerPixel = colorCount > alphabet.count * alphabet.count ? 3 : colorCount > alphabet.count ? 2 : 1
        let symbolCount = Int(pow(Double(alphabet.count), Double(charsPerPixel)))
        let palette = try xpmPalette(bitmap: bitmap, pixels: pixels, components: components,
                                     width: width, height: height, symbolCount: symbolCount)
        let output = xpmText(width: width, height: height, colors: palette.colors,
                             indices: palette.indices, charsPerPixel: charsPerPixel, alphabet: alphabet)
        guard let data = output.data(using: .utf8) else { throw MapFileError.cannotWrite }
        try data.write(to: url, options: .atomic)
    }

    private static func xpmPalette(
        bitmap: NSBitmapImageRep,
        pixels: UnsafeMutablePointer<UInt8>,
        components: Int,
        width: Int,
        height: Int,
        symbolCount: Int
    ) throws -> (colors: [XPMColor], indices: [Int]) {
        var accumulator = XPMAccumulator(count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * width + x
                let value = xpmColor(at: x, y: y, bitmap: bitmap, pixels: pixels, components: components)
                try accumulator.insert(value, at: pixelIndex, symbolCount: symbolCount)
            }
        }
        return (accumulator.colors, accumulator.indices)
    }

    private static func xpmColorKey(_ color: XPMColor) -> UInt32 {
        UInt32(color.r) << 24 | UInt32(color.g) << 16 | UInt32(color.b) << 8 | UInt32(color.a)
    }

    private static func xpmText(
        width: Int,
        height: Int,
        colors: [XPMColor],
        indices: [Int],
        charsPerPixel: Int,
        alphabet: [Character]
    ) -> String {
        var output = "/* XPM */\nstatic char * image[] = {\n"
        output += "\"\(width) \(height) \(colors.count) \(charsPerPixel)\",\n"
        for (index, color) in colors.enumerated() {
            let value = color.a < 128 ? "None" : String(format: "#%02X%02X%02X", color.r, color.g, color.b)
            output += "\"\(xpmSymbol(index, charsPerPixel: charsPerPixel, alphabet: alphabet)) c \(value)\",\n"
        }
        for y in 0..<height {
            let row = (0..<width).map { xpmSymbol(indices[y * width + $0], charsPerPixel: charsPerPixel, alphabet: alphabet) }.joined()
            output += "\"\(row)\"\(y == height - 1 ? "" : ",")\n"
        }
        return output + "};\n"
    }

    private static func xpmSymbol(_ index: Int, charsPerPixel: Int, alphabet: [Character]) -> String {
        var value = index
        var result = ""
        for _ in 0..<charsPerPixel {
            result.append(alphabet[value % alphabet.count])
            value /= alphabet.count
        }
        return result
    }

    private static func xpmColor(
        at x: Int,
        y: Int,
        bitmap: NSBitmapImageRep,
        pixels: UnsafeMutablePointer<UInt8>,
        components: Int
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let offset = y * bitmap.bytesPerRow + x * components
        if bitmap.bitmapFormat.contains(.alphaFirst) {
            return xpmAlphaFirstColor(at: offset, pixels: pixels, components: components, hasAlpha: bitmap.hasAlpha)
        }
        return xpmComponentColor(at: offset, pixels: pixels, components: components, hasAlpha: bitmap.hasAlpha)
    }

    private static func xpmAlphaFirstColor(
        at offset: Int,
        pixels: UnsafeMutablePointer<UInt8>,
        components: Int,
        hasAlpha: Bool
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let alphaOffset = hasAlpha ? 0 : -1
        let a = hasAlpha ? pixels[offset] : 255
        return (pixels[offset + alphaOffset + 1], pixels[offset + alphaOffset + 2], pixels[offset + alphaOffset + 3], a)
    }

    private static func xpmComponentColor(
        at offset: Int,
        pixels: UnsafeMutablePointer<UInt8>,
        components: Int,
        hasAlpha: Bool
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let r = pixels[offset]
        let g = components > 1 ? pixels[offset + 1] : r
        let b = components > 2 ? pixels[offset + 2] : g
        let a = hasAlpha ? pixels[offset + components - 1] : 255
        return (r, g, b, a)
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
        let footprint = palette.footprint(for: element)
        let target: NSRect
        if isDoubleHeight {
            target = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 2)
        } else if footprint.width > 1 || footprint.height > 1 {
            target = NSRect(
                x: rect.minX,
                y: rect.minY - rect.height * CGFloat(footprint.height - 1),
                width: rect.width * CGFloat(footprint.width),
                height: rect.height * CGFloat(footprint.height)
            )
        } else {
            target = rect
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: target.width, height: target.height))
        // Staggering changes each cell's origin, not its four-sided shape.
        // Double-height sprites intentionally remain unclipped so they can
        // project above their anchor cell.
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private static func drawSeaCoast(atX x: Int, y: Int, in rect: NSRect, map: MapState, atlas: SpriteAtlas, palette: SpritePalette) {
        guard !map.tileset.isGameBoyWarsFamily, map.backgroundDrawElement(atX: x, y: y) == .terrainSea else { return }
        let neighbours = coastNeighbours(atX: x, y: y, map: map)
        for (element, shouldDraw) in cornerCoastOverlays(neighbours) + edgeCoastOverlays(neighbours) where shouldDraw {
            draw(element, in: rect, map: map, atlas: atlas, palette: palette)
        }
    }

    private static func coastNeighbours(atX x: Int, y: Int, map: MapState) -> CoastNeighbours {
        CoastNeighbours(
            up: map.backgroundElement(atX: x, y: y - 1),
            down: map.backgroundElement(atX: x, y: y + 1),
            left: map.backgroundElement(atX: x - 1, y: y),
            right: map.backgroundElement(atX: x + 1, y: y),
            upLeft: map.backgroundElement(atX: x - 1, y: y - 1),
            upRight: map.backgroundElement(atX: x + 1, y: y - 1),
            downRight: map.backgroundElement(atX: x + 1, y: y + 1),
            downLeft: map.backgroundElement(atX: x - 1, y: y + 1)
        )
    }

    private static func cornerCoastOverlays(_ n: CoastNeighbours) -> [(Element, Bool)] {
        [
            (Element(AWConstants.makeTerrain(6, 3)), n.upLeft.isLand && !n.up.isLand && !n.left.isLand),
            (Element(AWConstants.makeTerrain(5, 3)), n.upRight.isLand && !n.up.isLand && !n.right.isLand),
            (Element(AWConstants.makeTerrain(5, 2)), n.downRight.isLand && !n.down.isLand && !n.right.isLand),
            (Element(AWConstants.makeTerrain(6, 2)), n.downLeft.isLand && !n.down.isLand && !n.left.isLand),
            (Element(AWConstants.makeTerrain(5, 0)), n.up.isLand && n.left.isLand),
            (Element(AWConstants.makeTerrain(6, 0)), n.up.isLand && n.right.isLand),
            (Element(AWConstants.makeTerrain(5, 1)), n.down.isLand && n.left.isLand),
            (Element(AWConstants.makeTerrain(6, 1)), n.down.isLand && n.right.isLand)
        ]
    }

    private static func edgeCoastOverlays(_ n: CoastNeighbours) -> [(Element, Bool)] {
        [
            (Element(AWConstants.makeTerrain(5, 4)), n.left.isLand),
            (Element(AWConstants.makeTerrain(5, 5)), n.up.isLand),
            (Element(AWConstants.makeTerrain(6, 4)), n.right.isLand),
            (Element(AWConstants.makeTerrain(6, 5)), n.down.isLand)
        ]
    }
}

private struct XPMAccumulator {
    var colors: [XPMColor] = []
    var indices: [Int]
    private var lookup: [UInt32: Int] = [:]

    init(count: Int) {
        indices = [Int](repeating: 0, count: count)
    }

    mutating func insert(_ color: XPMColor, at index: Int, symbolCount: Int) throws {
        let key = UInt32(color.r) << 24 | UInt32(color.g) << 16 | UInt32(color.b) << 8 | UInt32(color.a)
        if let existing = lookup[key] {
            indices[index] = existing
            return
        }
        let next = colors.count
        guard next < symbolCount else { throw MapFileError.cannotWrite }
        lookup[key] = next
        colors.append(color)
        indices[index] = next
    }
}

private struct CoastNeighbours {
    let up: Element
    let down: Element
    let left: Element
    let right: Element
    let upLeft: Element
    let upRight: Element
    let downRight: Element
    let downLeft: Element
}
