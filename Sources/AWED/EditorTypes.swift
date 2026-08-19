import Foundation
import AWEDCore

struct GridPoint: Hashable, Sendable {
    let x: Int
    let y: Int
}

struct SelectionRect: Equatable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var isEmpty: Bool { width <= 0 || height <= 0 }

    func contains(_ point: GridPoint) -> Bool {
        point.x >= x && point.x < x + width && point.y >= y && point.y < y + height
    }
}

enum EditorTool: String, CaseIterable, Identifiable, Sendable {
    case pencil
    case line
    case rectangle
    case filledRectangle
    case bucket
    case selector

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pencil: "Pencil"
        case .line: "Line"
        case .rectangle: "Square"
        case .filledRectangle: "Filled square"
        case .bucket: "Paint bucket"
        case .selector: "Selection tool"
        }
    }

    var systemImage: String {
        switch self {
        case .pencil: "pencil"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .filledRectangle: "rectangle.fill"
        case .bucket: "paintbrush.fill"
        case .selector: "rectangle.dashed"
        }
    }
}

enum EditorDialog: String, Identifiable {
    case information
    case settings
    case status
    case preferences
    case about

    var id: String { rawValue }
}

enum PendingDocumentAction: Equatable, Sendable {
    case new
    case open(URL)
}

enum PointerPhase: Sendable {
    case began
    case changed
    case ended
}

struct PointerModifiers: Sendable {
    var command = false
    var shift = false
    var option = false
}
