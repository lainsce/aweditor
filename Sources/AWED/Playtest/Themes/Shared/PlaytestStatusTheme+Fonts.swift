import AWEDCore
import SwiftUI

extension PlaytestStatusTheme {
    struct FontProfile {
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

    var fontProfile: FontProfile {
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
        case .superFamicomWars:
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
        case .gameBoyWars2, .gameBoyWars3:
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

    /// Font metadata used when a legacy menu sizes itself to its visible
    /// command labels. Keeping the measurement source next to the SwiftUI
    /// font construction prevents the rail from drifting when an era's face
    /// or point size changes.
    var legacyMenuFontFamily: String { fontProfile.family }

    var legacyMenuFontPointSize: CGFloat {
        switch self {
        case .famicomWars: 9
        case .superFamicomWars: 16
        default: fontProfile.bodySize
        }
    }

    func themedFont(
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

}
