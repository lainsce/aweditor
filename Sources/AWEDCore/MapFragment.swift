import Foundation

public struct MapFragment: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var background: [Element]
    public var backgroundDraw: [Element]
    public var foreground: [Element]

    public init(width: Int, height: Int, background: [Element], backgroundDraw: [Element], foreground: [Element]) {
        self.width = width
        self.height = height
        self.background = background
        self.backgroundDraw = backgroundDraw
        self.foreground = foreground
    }

    public init(map: MapState, x: Int, y: Int, width: Int, height: Int) {
        let safeWidth = max(0, width)
        let safeHeight = max(0, height)
        let arrays = Self.arrays(from: map, x: x, y: y, width: safeWidth, height: safeHeight)
        self.width = safeWidth
        self.height = safeHeight
        self.background = arrays.background
        self.backgroundDraw = arrays.backgroundDraw
        self.foreground = arrays.foreground
    }

    private static func arrays(
        from map: MapState,
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) -> (background: [Element], backgroundDraw: [Element], foreground: [Element]) {
        var background = Array(repeating: Element.terrainSea, count: width * height)
        var backgroundDraw = background
        var foreground = Array(repeating: Element.unitEmpty, count: width * height)
        for localX in 0..<width {
            for localY in 0..<height {
                let index = localX * height + localY
                background[index] = map.backgroundElement(atX: x + localX, y: y + localY)
                backgroundDraw[index] = map.backgroundDrawElement(atX: x + localX, y: y + localY)
                foreground[index] = map.foregroundElement(atX: x + localX, y: y + localY)
            }
        }
        return (background, backgroundDraw, foreground)
    }

    public func backgroundElement(atX x: Int, y: Int) -> Element {
        guard x >= 0, x < width, y >= 0, y < height else { return .terrainSea }
        return background[x * height + y]
    }

    public func foregroundElement(atX x: Int, y: Int) -> Element {
        guard x >= 0, x < width, y >= 0, y < height else { return .unitEmpty }
        return foreground[x * height + y]
    }

    public func backgroundDrawElement(atX x: Int, y: Int) -> Element {
        guard x >= 0, x < width, y >= 0, y < height else { return .terrainSea }
        return backgroundDraw[x * height + y]
    }

    public func bridgeUnderlayDrawElement(atX x: Int, y: Int) -> Element? {
        let bridge = backgroundElement(atX: x, y: y)
        guard bridge == .terrainBridgeH || bridge == .terrainBridgeV else { return nil }
        let neighbours = [
            backgroundElement(atX: x, y: y - 1),
            backgroundElement(atX: x, y: y + 1),
            backgroundElement(atX: x - 1, y: y),
            backgroundElement(atX: x + 1, y: y),
        ]
        guard neighbours.contains(where: { $0.simplified == .terrainRiver }) else {
            return .terrainSea
        }
        return bridge == .terrainBridgeH
            ? Element(AWConstants.makeTerrain(3, 1))
            : .terrainRiver
    }

    public func buildingUnderlayDrawElement(atX x: Int, y: Int) -> Element? {
        let building = backgroundElement(atX: x, y: y)
        guard building.isBuilding else { return nil }
        return building.simplified == .buildingPort ? .terrainShoal : .terrainPlain
    }

    public func clipped(toWidth newWidth: Int, height newHeight: Int) -> MapFragment {
        let safeWidth = min(max(0, newWidth), width)
        let safeHeight = min(max(0, newHeight), height)
        var clipped = MapFragment(
            width: safeWidth,
            height: safeHeight,
            background: Array(repeating: .terrainBlank, count: safeWidth * safeHeight),
            backgroundDraw: Array(repeating: .terrainBlank, count: safeWidth * safeHeight),
            foreground: Array(repeating: .unitEmpty, count: safeWidth * safeHeight)
        )
        for x in 0..<safeWidth {
            for y in 0..<safeHeight {
                clipped.setBackground(backgroundElement(atX: x, y: y), atX: x, y: y)
                clipped.setBackgroundDraw(backgroundDrawElement(atX: x, y: y), atX: x, y: y)
                clipped.setForeground(foregroundElement(atX: x, y: y), atX: x, y: y)
            }
        }
        return clipped
    }

    public mutating func setBackground(_ element: Element, atX x: Int, y: Int) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        background[x * height + y] = element
    }

    public mutating func setBackgroundDraw(_ element: Element, atX x: Int, y: Int) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        backgroundDraw[x * height + y] = element
    }

    public mutating func setForeground(_ element: Element, atX x: Int, y: Int) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        foreground[x * height + y] = element
    }
}
