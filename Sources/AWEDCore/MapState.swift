import Foundation

public struct MapState: Codable, Equatable, Sendable {
    public internal(set) var background: [Element]
    public internal(set) var backgroundDraw: [Element]
    public internal(set) var foreground: [Element]

    public internal(set) var width: Int
    public internal(set) var height: Int
    public var tileset: Tileset
    public var name: String
    public var author: String
    public var description: String
    public internal(set) var isDirty: Bool

    public init(
        width: Int = AWConstants.mapDefaultWidth,
        height: Int = AWConstants.mapDefaultHeight,
        tileset: Tileset = .normal,
        defaultTerrain: Element = .terrainSea,
        defaultAuthor: String = "Unknown"
    ) {
        let safeWidth = min(max(width, AWConstants.mapMinimumWidth), AWConstants.mapMaximumWidth)
        let safeHeight = min(max(height, AWConstants.mapMinimumHeight), AWConstants.mapMaximumHeight)
        self.width = safeWidth
        self.height = safeHeight
        self.tileset = tileset
        self.name = "Untitled"
        self.author = String(defaultAuthor.prefix(AWConstants.authorMaximumLength))
        self.description = ""
        let count = safeWidth * safeHeight
        self.background = Array(repeating: defaultTerrain, count: count)
        self.backgroundDraw = Array(repeating: defaultTerrain, count: count)
        self.foreground = Array(repeating: .unitEmpty, count: count)
        self.isDirty = false
        updateDraw()
    }

    public func backgroundElement(atX x: Int, y: Int) -> Element {
        guard isValid(x: x, y: y) else { return .terrainSea }
        return background[index(x: x, y: y)]
    }

    public func backgroundDrawElement(atX x: Int, y: Int) -> Element {
        guard isValid(x: x, y: y) else { return .terrainSea }
        return backgroundDraw[index(x: x, y: y)]
    }

    /// The bridge atlas cells are transparent overlays. Reconstruct the water
    /// plate beneath them from neighbouring river tiles, falling back to sea
    /// for coastal bridges and isolated legacy/imported bridge cells.
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
        // A horizontal bridge crosses the vertical river sprite and vice
        // versa. GB-family flat river sheets safely map either slot to their
        // one maintained river cell.
        return bridge == .terrainBridgeH
            ? Element(AWConstants.makeTerrain(3, 1))
            : .terrainRiver
    }

    /// Building artwork is composited over terrain rather than carrying an
    /// opaque plate. Ports sit in shoal water; every other property stands on
    /// the artstyle's plains tile.
    public func buildingUnderlayDrawElement(atX x: Int, y: Int) -> Element? {
        let building = backgroundElement(atX: x, y: y)
        guard building.isBuilding else { return nil }
        return building.simplified == .buildingPort ? .terrainShoal : .terrainPlain
    }

    public func foregroundElement(atX x: Int, y: Int) -> Element {
        guard isValid(x: x, y: y) else { return .unitEmpty }
        return foreground[index(x: x, y: y)]
    }

    public mutating func setName(_ value: String) {
        name = String(value.prefix(AWConstants.nameMaximumLength))
        isDirty = true
    }

    public mutating func setAuthor(_ value: String) {
        author = String(value.prefix(AWConstants.authorMaximumLength))
        isDirty = true
    }

    public mutating func setDescription(_ value: String) {
        description = String(value.prefix(AWConstants.descriptionMaximumLength))
        isDirty = true
    }

    public mutating func setDirty(_ dirty: Bool = true) {
        isDirty = dirty
    }

    @discardableResult
    public mutating func setBackground(_ element: Element, atX x: Int, y: Int, check: Bool = true) -> Bool {
        // HQ ownership is meaningful only for a playable army. A neutral HQ
        // is the defeated-army representation used by older maps, so keep it
        // as a neutral City in the live map and never let it become a placeable
        // property of its own.
        let normalizedElement = normalizedBackgroundElement(element)
        guard isValid(x: x, y: y), !check || allowPlacement(normalizedElement, atX: x, y: y) else { return false }
        background[index(x: x, y: y)] = normalizedElement
        updateDraw(x: x - 2, y: y - 2, width: 5, height: 5)
        isDirty = true
        return true
    }

    @discardableResult
    public mutating func setForeground(_ element: Element, atX x: Int, y: Int) -> Bool {
        guard isValid(x: x, y: y), allowPlacement(element, atX: x, y: y) else { return false }
        foreground[index(x: x, y: y)] = element
        isDirty = true
        return true
    }

    func index(x: Int, y: Int) -> Int { x * height + y }
    func isValid(x: Int, y: Int) -> Bool { x >= 0 && x < width && y >= 0 && y < height }

    func normalizedBackgroundElement(_ element: Element) -> Element {
        guard element.isBuilding,
              element.simplified == .buildingHQ,
              element.army == AWConstants.armyNeutral else { return element }
        return Element.buildingCity.changedArmy(AWConstants.armyNeutral)
    }
}

public enum Compatibility: Int, Codable, Sendable {
    case impossible = 0
    case ok = 1
    case truncate = 2
}
