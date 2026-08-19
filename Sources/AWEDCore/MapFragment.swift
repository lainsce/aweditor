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
        self.width = max(0, width)
        self.height = max(0, height)
        var background = Array(repeating: Element.terrainSea, count: self.width * self.height)
        var backgroundDraw = background
        var foreground = Array(repeating: Element.unitEmpty, count: self.width * self.height)
        for localX in 0..<self.width {
            for localY in 0..<self.height {
                let index = localX * self.height + localY
                background[index] = map.backgroundElement(atX: x + localX, y: y + localY)
                backgroundDraw[index] = map.backgroundDrawElement(atX: x + localX, y: y + localY)
                foreground[index] = map.foregroundElement(atX: x + localX, y: y + localY)
            }
        }
        self.background = background
        self.backgroundDraw = backgroundDraw
        self.foreground = foreground
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
