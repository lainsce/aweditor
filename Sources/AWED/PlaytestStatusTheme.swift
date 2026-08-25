import AWEDCore
import SwiftUI

enum PlaytestStatusTheme: Equatable {
    case famicomWars
    case gameBoyWars
    case superFamicomWars
    case gameBoyWars2
    case gameBoyWars3
    case advanceWars
    case advanceWars2
    case dualStrike
    case daysOfRuin

    // Measured from a classic Game Boy display rather than the brighter
    // generic DMG palette commonly used by emulators.
    private static let gameBoyBlack = rgb(0x1B2A09)
    private static let gameBoyDarkGray = rgb(0x0E450B)
    private static let gameBoyLightGray = rgb(0x496B22)
    private static let gameBoyWhite = rgb(0x9A9E3F)

    init(tileset: Tileset) {
        switch tileset {
        case .famicomWars: self = .famicomWars
        case .gbWars: self = .gameBoyWars
        case .superFamicomWars: self = .superFamicomWars
        case .gbWars2: self = .gameBoyWars2
        case .gbWars3: self = .gameBoyWars3
        case .aw1: self = .advanceWars
        case .aw2: self = .advanceWars2
        case .normal, .snow, .desert, .wasteland: self = .dualStrike
        case .daysOfRuin: self = .daysOfRuin
        }
    }

    // These values describe the games' compact map/status popups, rather than
    // borrowing the more decorative chrome from their title and CO screens.
    var surface: Color {
        switch self {
        case .famicomWars:
            Self.rgb(0x000000)
        case .gameBoyWars:
            Self.gameBoyWhite
        case .superFamicomWars:
            Self.rgb555(19, 9, 11)
        case .gameBoyWars2:
            Self.rgb555(29, 31, 31)
        case .gameBoyWars3:
            Self.rgb555(31, 31, 29)
        case .advanceWars, .advanceWars2:
            Self.rgb555(4, 5, 1)
        case .dualStrike:
            Self.rgb555(3, 4, 2)
        case .daysOfRuin:
            Self.rgb555(4, 4, 3)
        }
    }

    var surfaceOpacity: Double {
        switch self {
        case .advanceWars: 0.80
        case .advanceWars2: 0.82
        case .dualStrike: 0.84
        case .daysOfRuin: 0.88
        default: 1
        }
    }

    var primaryText: Color {
        switch self {
        case .famicomWars:
            Self.rgb(0xFCFCFC)
        case .gameBoyWars:
            Self.gameBoyBlack
        case .superFamicomWars:
            Self.rgb555(31, 29, 27)
        case .gameBoyWars2:
            Self.rgb555(0, 1, 4)
        case .gameBoyWars3:
            Self.rgb555(1, 2, 1)
        case .advanceWars, .advanceWars2, .dualStrike:
            Self.rgb555(31, 31, 29)
        case .daysOfRuin:
            Self.rgb555(29, 28, 24)
        }
    }

    var secondaryText: Color {
        switch self {
        case .famicomWars:
            Self.rgb(0xBCBCBC)
        case .gameBoyWars:
            Self.gameBoyDarkGray
        case .superFamicomWars:
            Self.rgb555(29, 20, 21)
        case .gameBoyWars2:
            Self.rgb555(3, 13, 31)
        case .gameBoyWars3:
            Self.rgb555(3, 10, 27)
        case .advanceWars, .advanceWars2, .dualStrike:
            Self.rgb555(25, 27, 20)
        case .daysOfRuin:
            Self.rgb555(21, 20, 17)
        }
    }

    var outerBorder: Color {
        switch self {
        case .famicomWars: Self.rgb(0x7C7C7C)
        case .gameBoyWars: Self.gameBoyBlack
        case .superFamicomWars: Self.rgb555(5, 2, 4)
        case .gameBoyWars2: Self.rgb555(0, 1, 4)
        case .gameBoyWars3: Self.rgb555(1, 2, 1)
        case .daysOfRuin: Self.rgb555(1, 1, 1)
        case .advanceWars, .advanceWars2, .dualStrike: .clear
        }
    }

    var innerBorder: Color {
        switch self {
        case .famicomWars: Self.rgb(0xFCFCFC)
        case .gameBoyWars: Self.gameBoyLightGray
        case .superFamicomWars: Self.rgb555(29, 20, 21)
        case .gameBoyWars2: Self.rgb555(18, 27, 31)
        case .gameBoyWars3: Self.rgb555(12, 22, 5)
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin: .clear
        }
    }

    // Border widths are measured in physical screen pixels. The view converts
    // them with displayScale so a requested 1 px rule remains 1 px on Retina.
    var outerBorderPixels: CGFloat {
        switch self {
        case .advanceWars, .advanceWars2, .dualStrike: 0
        default: 1
        }
    }

    var innerBorderPixels: CGFloat {
        switch self {
        case .famicomWars, .gameBoyWars, .superFamicomWars, .gameBoyWars2, .gameBoyWars3: 1
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin: 0
        }
    }

    var innerBorderInsetPixels: CGFloat {
        switch self {
        case .famicomWars, .superFamicomWars, .gameBoyWars3: 3
        case .gameBoyWars, .gameBoyWars2: 2
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin: 0
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .famicomWars: 4
        case .superFamicomWars: 2
        default: 0
        }
    }

    var contentPadding: CGFloat {
        switch self {
        case .famicomWars, .gameBoyWars, .superFamicomWars, .gameBoyWars2, .gameBoyWars3: 10
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin: 9
        }
    }

    var preferredColorScheme: ColorScheme {
        switch self {
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3: .light
        default: .dark
        }
    }

    private struct FontProfile {
        let family: String
        let bodySize: CGFloat
        let titleSize: CGFloat
        let detailSize: CGFloat
        let valueSize: CGFloat
        let bodyWeight: Font.Weight
        let titleWeight: Font.Weight
        let detailWeight: Font.Weight
        let valueWeight: Font.Weight
    }

    private var fontProfile: FontProfile {
        switch self {
        case .famicomWars:
            FontProfile(
                family: "Press Start 2P",
                bodySize: 12,
                titleSize: 12,
                detailSize: 8,
                valueSize: 9,
                bodyWeight: .regular,
                titleWeight: .regular,
                detailWeight: .regular,
                valueWeight: .regular
            )
        case .gameBoyWars:
            FontProfile(
                family: "VT323",
                bodySize: 18,
                titleSize: 21,
                detailSize: 14,
                valueSize: 15,
                bodyWeight: .regular,
                titleWeight: .regular,
                detailWeight: .regular,
                valueWeight: .regular
            )
        case .superFamicomWars, .gameBoyWars2, .gameBoyWars3:
            FontProfile(
                family: "Silkscreen",
                bodySize: 13,
                titleSize: 15,
                detailSize: 10,
                valueSize: 11,
                bodyWeight: .regular,
                titleWeight: .bold,
                detailWeight: .bold,
                valueWeight: .bold
            )
        case .advanceWars, .advanceWars2:
            FontProfile(
                family: "Share Tech Mono",
                bodySize: 13,
                titleSize: 16,
                detailSize: 11,
                valueSize: 12,
                bodyWeight: .regular,
                titleWeight: .regular,
                detailWeight: .regular,
                valueWeight: .regular
            )
        case .dualStrike:
            FontProfile(
                family: "Rajdhani",
                bodySize: 14,
                titleSize: 17,
                detailSize: 11,
                valueSize: 12,
                bodyWeight: .regular,
                titleWeight: .semibold,
                detailWeight: .semibold,
                valueWeight: .semibold
            )
        case .daysOfRuin:
            FontProfile(
                family: "Rajdhani",
                bodySize: 14,
                titleSize: 18,
                detailSize: 12,
                valueSize: 12,
                bodyWeight: .regular,
                titleWeight: .semibold,
                detailWeight: .semibold,
                valueWeight: .semibold
            )
        }
    }

    private func themedFont(
        _ size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        weight: Font.Weight
    ) -> Font {
        .custom(fontProfile.family, size: size, relativeTo: textStyle)
            .weight(weight)
    }

    var bodyFont: Font {
        themedFont(
            fontProfile.bodySize,
            relativeTo: .body,
            weight: fontProfile.bodyWeight
        )
    }

    var titleFont: Font {
        themedFont(
            fontProfile.titleSize,
            relativeTo: .headline,
            weight: fontProfile.titleWeight
        )
    }

    var detailFont: Font {
        themedFont(
            fontProfile.detailSize,
            relativeTo: .caption,
            weight: fontProfile.detailWeight
        )
    }

    var valueFont: Font {
        themedFont(
            fontProfile.valueSize,
            relativeTo: .callout,
            weight: fontProfile.valueWeight
        )
    }

    var shadow: (color: Color, radius: CGFloat, xPixels: CGFloat, yPixels: CGFloat) {
        switch self {
        case .superFamicomWars:
            (Self.rgb555(5, 2, 4).opacity(0.72), 0, 1, 1)
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            (outerBorder.opacity(0.58), 0, 1, 1)
        default:
            (.clear, 0, 0, 0)
        }
    }

    var warningText: Color {
        switch self {
        case .famicomWars: Self.rgb(0xF83800)
        case .gameBoyWars: Self.gameBoyDarkGray
        case .superFamicomWars: Self.rgb555(31, 18, 12)
        case .gameBoyWars2: Self.rgb555(27, 4, 3)
        case .gameBoyWars3: Self.rgb555(27, 4, 3)
        case .advanceWars, .advanceWars2, .dualStrike: Self.rgb555(31, 16, 2)
        case .daysOfRuin: Self.rgb555(24, 8, 5)
        }
    }

    var resourceTint: Color {
        switch self {
        case .famicomWars: Self.rgb(0x00B800)
        case .gameBoyWars: Self.gameBoyDarkGray
        case .superFamicomWars: Self.rgb555(29, 20, 21)
        case .gameBoyWars2: Self.rgb555(3, 13, 31)
        case .gameBoyWars3: Self.rgb555(3, 10, 27)
        case .advanceWars, .advanceWars2, .dualStrike: Self.rgb555(5, 17, 29)
        case .daysOfRuin: Self.rgb555(20, 17, 12)
        }
    }

    var buttonCornerRadius: CGFloat {
        switch self {
        case .famicomWars, .gameBoyWars, .gameBoyWars2, .gameBoyWars3: 0
        case .superFamicomWars: 2
        case .advanceWars, .advanceWars2, .dualStrike: 5
        case .daysOfRuin: 1
        }
    }

    var buttonMinHeight: CGFloat {
        switch self {
        case .famicomWars, .gameBoyWars, .gameBoyWars2, .gameBoyWars3: 28
        default: 32
        }
    }

    var buttonBorder: Color {
        switch self {
        case .famicomWars: Self.rgb(0xFCFCFC)
        case .gameBoyWars: Self.gameBoyBlack
        case .superFamicomWars: Self.rgb555(5, 2, 4)
        case .gameBoyWars2: Self.rgb555(0, 1, 4)
        case .gameBoyWars3: Self.rgb555(1, 2, 1)
        case .advanceWars, .advanceWars2: Self.rgb555(2, 5, 10)
        case .dualStrike: Self.rgb555(1, 3, 4)
        case .daysOfRuin: Self.rgb555(1, 1, 1)
        }
    }

    var buttonUpperEdge: Color {
        switch self {
        case .famicomWars: Self.rgb(0xBCBCBC)
        case .gameBoyWars: Self.gameBoyWhite
        case .superFamicomWars: Self.rgb555(31, 24, 22)
        case .gameBoyWars2: Self.rgb555(29, 31, 31)
        case .gameBoyWars3: Self.rgb555(31, 31, 29)
        case .advanceWars, .advanceWars2: Self.rgb555(31, 31, 25)
        case .dualStrike: Self.rgb555(22, 28, 29)
        case .daysOfRuin: Self.rgb555(22, 20, 15)
        }
    }

    var buttonLowerEdge: Color {
        switch self {
        case .famicomWars: Self.rgb(0x7C7C7C)
        case .gameBoyWars: Self.gameBoyDarkGray
        case .superFamicomWars: Self.rgb555(8, 3, 5)
        case .gameBoyWars2: Self.rgb555(3, 13, 31)
        case .gameBoyWars3: Self.rgb555(3, 10, 2)
        case .advanceWars, .advanceWars2: Self.rgb555(3, 8, 14)
        case .dualStrike: Self.rgb555(2, 6, 8)
        case .daysOfRuin: Self.rgb555(3, 3, 2)
        }
    }

    func buttonSurface(tone: PlaytestEraButtonStyle.Tone, pressed: Bool) -> Color {
        if pressed { return buttonLowerEdge }

        return switch (self, tone) {
        case (.famicomWars, .primary): Self.rgb(0xF83800)
        case (.famicomWars, .neutral): Self.rgb(0x3CBCFC)
        case (.gameBoyWars, .primary): Self.gameBoyDarkGray
        case (.gameBoyWars, .neutral): Self.gameBoyLightGray
        case (.superFamicomWars, .primary): Self.rgb555(29, 20, 21)
        case (.superFamicomWars, .neutral): Self.rgb555(17, 10, 13)
        case (.gameBoyWars2, .primary): Self.rgb555(3, 13, 31)
        case (.gameBoyWars2, .neutral): Self.rgb555(18, 27, 31)
        case (.gameBoyWars3, .primary): Self.rgb555(12, 22, 5)
        case (.gameBoyWars3, .neutral): Self.rgb555(27, 29, 19)
        case (.advanceWars, .primary), (.advanceWars2, .primary): Self.rgb555(28, 14, 2)
        case (.advanceWars, .neutral), (.advanceWars2, .neutral): Self.rgb555(4, 12, 20)
        case (.dualStrike, .primary): Self.rgb555(4, 18, 24)
        case (.dualStrike, .neutral): Self.rgb555(6, 10, 9)
        case (.daysOfRuin, .primary): Self.rgb555(20, 12, 5)
        case (.daysOfRuin, .neutral): Self.rgb555(9, 9, 7)
        }
    }

    func buttonText(tone: PlaytestEraButtonStyle.Tone) -> Color {
        switch (self, tone) {
        case (.gameBoyWars, .primary): Self.gameBoyWhite
        case (.gameBoyWars2, .primary): Self.rgb555(29, 31, 31)
        case (.gameBoyWars3, .primary): Self.rgb555(31, 31, 29)
        case (.gameBoyWars2, .neutral), (.gameBoyWars3, .neutral): buttonBorder
        default: primaryText
        }
    }

    var meterTrack: Color {
        switch self {
        case .famicomWars: Self.rgb(0x000000)
        case .gameBoyWars: Self.gameBoyLightGray
        case .superFamicomWars: Self.rgb555(8, 3, 5)
        case .gameBoyWars2: Self.rgb555(18, 27, 31)
        case .gameBoyWars3: Self.rgb555(27, 29, 19)
        case .advanceWars, .advanceWars2: Self.rgb555(2, 5, 10)
        case .dualStrike: Self.rgb555(1, 3, 4)
        case .daysOfRuin: Self.rgb555(3, 3, 2)
        }
    }

    var meterBorder: Color { buttonBorder }

    var meterDivider: Color {
        switch self {
        case .famicomWars: Self.rgb(0x000000)
        case .gameBoyWars: Self.gameBoyBlack
        case .superFamicomWars: Self.rgb555(5, 2, 4)
        case .gameBoyWars2: Self.rgb555(0, 1, 4)
        case .gameBoyWars3: Self.rgb555(1, 2, 1)
        case .advanceWars, .advanceWars2, .dualStrike: surface
        case .daysOfRuin: Self.rgb555(1, 1, 1)
        }
    }

    var meterSegmentCount: Int {
        switch self {
        case .famicomWars, .gameBoyWars: 8
        case .superFamicomWars, .gameBoyWars2, .gameBoyWars3: 10
        case .advanceWars, .advanceWars2, .dualStrike: 10
        case .daysOfRuin: 5
        }
    }

    var meterHeight: CGFloat {
        switch self {
        case .famicomWars, .gameBoyWars, .gameBoyWars2, .gameBoyWars3: 8
        case .superFamicomWars: 9
        case .advanceWars, .advanceWars2, .dualStrike: 10
        case .daysOfRuin: 11
        }
    }

    var meterCornerRadius: CGFloat {
        switch self {
        case .advanceWars, .advanceWars2, .dualStrike: 3
        default: 0
        }
    }

    func armyAccent(_ army: Int) -> Color {
        if self == .gameBoyWars {
            return army == AWConstants.armyBlueMoon ? Self.gameBoyWhite : Self.gameBoyBlack
        }
        if self == .gameBoyWars2 {
            return army == AWConstants.armyBlueMoon ? Self.rgb555(18, 27, 31) : Self.rgb555(0, 1, 4)
        }
        if self == .gameBoyWars3 {
            return army == AWConstants.armyBlueMoon ? Self.rgb555(29, 31, 31) : Self.rgb555(27, 4, 3)
        }
        if self == .daysOfRuin, army == AWConstants.armyBlackHole {
            return Self.rgb555(3, 3, 3)
        }

        return switch army {
        case AWConstants.armyOrangeStar:
            self == .famicomWars ? Self.rgb(0xF83800) : Self.rgb555(29, 6, 3)
        case AWConstants.armyBlueMoon:
            self == .famicomWars ? Self.rgb(0x0058F8) : Self.rgb555(4, 13, 28)
        case AWConstants.armyGreenEarth:
            self == .famicomWars ? Self.rgb(0x00B800) : Self.rgb555(4, 19, 7)
        case AWConstants.armyYellowComet:
            self == .famicomWars ? Self.rgb(0xF8B800) : Self.rgb555(29, 22, 2)
        case AWConstants.armyBlackHole:
            Self.rgb555(12, 7, 18)
        default:
            innerBorder
        }
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private static func rgb555(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(red: Double(red) / 31, green: Double(green) / 31, blue: Double(blue) / 31)
    }
}
