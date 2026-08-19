import Foundation

public enum MapFileError: Error, LocalizedError, Sendable {
    case unreadableHeader
    case unsupportedHeader
    case truncatedFile
    case invalidDimensions
    case incompatibleDimensions
    case invalidAWSDimensions
    case cannotWrite

    public var errorDescription: String? {
        switch self {
        case .unreadableHeader: "The selected file does not contain a complete map header."
        case .unsupportedHeader: "The selected file is not a supported Advance Wars map."
        case .truncatedFile: "The selected map file is incomplete or corrupted."
        case .invalidDimensions: "The map dimensions are outside the supported range."
        case .incompatibleDimensions: "This map is smaller than the 30×20 dimensions required by older formats."
        case .invalidAWSDimensions: "AWS maps can be at most 255×255 tiles."
        case .cannotWrite: "The map could not be written to the selected location."
        }
    }
}

public struct MapWriteReport: Equatable, Sendable {
    public let format: MapFormat
    public let warnings: [String]

    public init(format: MapFormat, warnings: [String] = []) {
        self.format = format
        self.warnings = warnings
    }
}

public enum MapFileCodec {
    public static func warnings(for map: MapState, format: MapFormat) -> [String] {
        var warnings: [String] = []
        if map.compatibleSize(with: format) == .truncate {
            warnings.append("The saved map will be cropped to 30×20 for the selected legacy format.")
        }
        if map.compatibleElements(with: format) == .truncate {
            warnings.append("Some tiles are not available in the selected format and will be converted when saved.")
        }
        return warnings
    }

    public static func read(from url: URL, defaultAuthor: String = "unknown") throws -> MapState {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw MapFileError.truncatedFile }
        var reader = ByteReader(data: data)
        let headerBytes = try reader.read(count: 10)
        guard let header = String(bytes: headerBytes.prefix(9), encoding: .ascii), let format = Element.mapType(for: header) else {
            throw MapFileError.unsupportedHeader
        }

        var width = 30
        var height = 20
        if format == .aws {
            width = Int(try reader.readUInt8())
            height = Int(try reader.readUInt8())
            guard width > 0, height > 0 else { throw MapFileError.invalidDimensions }
        }

        var map = MapState(width: width, height: height, tileset: .normal, defaultTerrain: .terrainSea, defaultAuthor: defaultAuthor)
        if format == .awd {
            let rawTileset = try reader.readUInt8()
            map.tileset = Tileset(rawValue: max(0, Int(rawTileset) - 1)) ?? .normal
        } else if format == .aws {
            map.tileset = Tileset(rawValue: Int(try reader.readUInt8())) ?? .normal
        } else {
            map.tileset = format == .awm ? .aw1 : .aw2
        }

        for x in 0..<width {
            for y in 0..<height {
                let value = Int(try reader.readUInt16())
                _ = map.setBackground(Element(value, mapType: format), atX: x, y: y, check: false)
            }
        }
        for x in 0..<width {
            for y in 0..<height {
                let value = Int(try reader.readUInt16())
                _ = map.setForeground(Element(value, mapType: format), atX: x, y: y)
            }
        }

        if reader.remaining >= 4 {
            map.setName(try reader.readStringField(maximum: AWConstants.nameMaximumLength))
        }
        if reader.remaining >= 4 {
            map.setAuthor(try reader.readStringField(maximum: AWConstants.authorMaximumLength))
        }
        if reader.remaining >= 4 {
            map.setDescription(try reader.readStringField(maximum: AWConstants.descriptionMaximumLength))
        }
        map.setDirty(false)
        map.updateDraw()
        return map
    }

    @discardableResult
    public static func write(_ map: MapState, to url: URL, format explicitFormat: MapFormat? = nil) throws -> MapWriteReport {
        let format = explicitFormat ?? MapFormat(fileExtension: url.pathExtension)
        let sizeCompatibility = map.compatibleSize(with: format)
        if sizeCompatibility == .impossible { throw MapFileError.incompatibleDimensions }
        if format == .aws && (map.width > 255 || map.height > 255) { throw MapFileError.invalidAWSDimensions }

        let warnings = Self.warnings(for: map, format: format)

        var data = Data()
        data.append(contentsOf: format.header.utf8)
        data.append(0)
        if format == .aws {
            data.append(UInt8(map.width))
            data.append(UInt8(map.height))
            data.append(UInt8(map.tileset.rawValue))
        } else if format == .awd {
            data.append(UInt8(min(255, map.tileset.rawValue + 1)))
        }

        let outputWidth = format.supportsVariableSize ? map.width : 30
        let outputHeight = format.supportsVariableSize ? map.height : 20
        for x in 0..<outputWidth {
            for y in 0..<outputHeight {
                let element = map.backgroundElement(atX: x, y: y)
                data.append(contentsOf: UInt16(clamping: element.converted(to: format)).littleEndianBytes)
            }
        }
        for x in 0..<outputWidth {
            for y in 0..<outputHeight {
                let element = map.foregroundElement(atX: x, y: y)
                data.append(contentsOf: UInt16(clamping: element.converted(to: format)).littleEndianBytes)
            }
        }

        appendStringField(map.name, to: &data)
        appendStringField(map.author, to: &data)
        appendStringField(map.description, to: &data)
        do { try data.write(to: url, options: .atomic) } catch { throw MapFileError.cannotWrite }
        return MapWriteReport(format: format, warnings: warnings)
    }

    private static func appendStringField(_ string: String, to data: inout Data) {
        let field = Data(string.utf8)
        data.append(contentsOf: UInt32(field.count).littleEndianBytes)
        data.append(field)
    }
}

private struct ByteReader {
    let data: Data
    var offset: Int = 0

    var remaining: Int { data.count - offset }

    mutating func read(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else { throw MapFileError.truncatedFile }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else { throw MapFileError.truncatedFile }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = try read(count: 2)
        return UInt16(bytes[bytes.startIndex]) | UInt16(bytes[bytes.startIndex + 1]) << 8
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try read(count: 4)
        return UInt32(bytes[bytes.startIndex]) | UInt32(bytes[bytes.startIndex + 1]) << 8 |
            UInt32(bytes[bytes.startIndex + 2]) << 16 | UInt32(bytes[bytes.startIndex + 3]) << 24
    }

    mutating func readStringField(maximum: Int) throws -> String {
        let length = Int(try readUInt32())
        guard length >= 0, length <= remaining else { throw MapFileError.truncatedFile }
        let data = try read(count: length)
        let clipped = data.prefix(maximum)
        return String(decoding: clipped, as: UTF8.self)
    }
}

private extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }
}
