import AWEDCore
import SwiftUI

extension PlaytestStatusTheme {
    /// Era-specific map strength readouts.  The original cartridge UIs use
    /// small opaque number blocks, not the rounded translucent badge that is
    /// appropriate for the modern editor chrome.
    var damageBadgeTheme: PlaytestDamageBadgeTheme {
        switch self {
        case .famicomWars:
            PlaytestDamageBadgeTheme(
                background: FamicomPPUPalette.black,
                border: FamicomPPUPalette.gray,
                text: FamicomPPUPalette.white,
                font: themedFont(6, relativeTo: .caption, weight: .regular),
                size: CGSize(width: 12, height: 10),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: FamicomPPUPalette.black,
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.95
            )

        case .gameBoyWars:
            PlaytestDamageBadgeTheme(
                background: Self.gameBoyBlack,
                border: Self.gameBoyDarkGray,
                text: Self.gameBoyWhite,
                font: themedFont(9, relativeTo: .caption, weight: .regular),
                size: CGSize(width: 13, height: 10),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: Self.gameBoyDarkGray,
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.9
            )

        case .superFamicomWars:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(5, 2, 4),
                border: Self.rgb555(29, 20, 21),
                text: Self.rgb555(31, 29, 27),
                font: themedFont(9, relativeTo: .caption, weight: .regular),
                size: CGSize(width: 14, height: 11),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: Self.rgb555(1, 1, 2),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.9
            )

        case .gameBoyWars2:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(0, 1, 4),
                border: Self.rgb555(18, 27, 31),
                text: Self.rgb555(31, 31, 29),
                font: themedFont(8, relativeTo: .caption, weight: .bold),
                size: CGSize(width: 13, height: 10),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: Self.rgb555(0, 1, 4),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.85
            )

        case .gameBoyWars3:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(0, 8, 20),
                border: Self.rgb555(0, 22, 31),
                text: Self.rgb555(31, 31, 23),
                font: themedFont(8, relativeTo: .caption, weight: .bold),
                size: CGSize(width: 13, height: 10),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: Self.rgb555(0, 3, 8),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.85
            )

        case .advanceWars:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(2, 2, 2),
                border: Self.rgb555(15, 16, 14),
                text: Self.rgb555(31, 31, 29),
                font: themedFont(8, relativeTo: .caption, weight: .regular),
                size: CGSize(width: 14, height: 10),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: Self.rgb555(0, 0, 0),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.75
            )

        case .advanceWars2:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(2, 4, 7),
                border: Self.rgb555(17, 23, 27),
                text: Self.rgb555(31, 31, 29),
                font: themedFont(8, relativeTo: .caption, weight: .regular),
                size: CGSize(width: 14, height: 10),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: Self.rgb555(0, 1, 3),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.75
            )

        case .dualStrike:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(2, 7, 10),
                border: buttonBorder,
                text: primaryText,
                font: themedFont(9, relativeTo: .caption, weight: .semibold),
                size: CGSize(width: 15, height: 11),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 2,
                borderWidth: 1,
                shadow: Self.rgb555(0, 1, 2),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.55
            )

        case .daysOfRuin:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(8, 6, 5),
                border: Self.rgb555(20, 16, 11),
                text: Self.rgb555(29, 28, 24),
                font: themedFont(9, relativeTo: .caption, weight: .semibold),
                size: CGSize(width: 15, height: 11),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 1,
                borderWidth: 1,
                shadow: Self.rgb555(1, 1, 1),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.6
            )
        }
    }

}
