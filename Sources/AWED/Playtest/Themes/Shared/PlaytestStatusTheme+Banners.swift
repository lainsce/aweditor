import AWEDCore
import SwiftUI

extension PlaytestStatusTheme {
    /// The day banner is deliberately separate from the status-card surface.
    /// Each game family gets the compact, low-resolution treatment associated
    /// with its hardware generation instead of inheriting the editor's glass.
    var bannerTheme: PlaytestBannerTheme {
        switch self {
        case .famicomWars:
            PlaytestBannerTheme(
                treatment: .famicomWars,
                titleFont: themedFont(16, relativeTo: .title2, weight: .regular),
                titleColor: FamicomPPUPalette.white,
                surface: FamicomPPUPalette.black,
                secondarySurface: FamicomPPUPalette.green,
                border: FamicomPPUPalette.green,
                innerBorder: .clear,
                shadow: FamicomPPUPalette.black,
                cornerRadius: 3,
                borderPixels: 2,
                shadowRadius: 0,
                shadowYOffset: 0
            )
        case .gameBoyWars:
            PlaytestBannerTheme(
                treatment: .gameBoyWars,
                titleFont: themedFont(27, relativeTo: .title, weight: .regular),
                titleColor: Self.gameBoyBlack,
                surface: Self.gameBoyWhite,
                secondarySurface: Self.gameBoyLightGray,
                border: Self.gameBoyBlack,
                innerBorder: Self.gameBoyDarkGray,
                shadow: Self.gameBoyDarkGray,
                cornerRadius: 0,
                borderPixels: 1,
                shadowRadius: 0,
                shadowYOffset: 1
            )
        case .superFamicomWars:
            PlaytestBannerTheme(
                treatment: .superFamicomWars,
                titleFont: themedFont(18, relativeTo: .title2, weight: .regular),
                titleColor: Self.rgb(0xC8B1FF),
                surface: Self.rgb(0x673A2A),
                secondarySurface: Self.rgb(0x7B4936),
                border: Self.rgb(0x1F2730),
                innerBorder: Self.rgb(0x89949D),
                shadow: Self.rgb(0x160C0A),
                cornerRadius: 0,
                borderPixels: 1,
                shadowRadius: 1,
                shadowYOffset: 2
            )
        case .gameBoyWars2:
            PlaytestBannerTheme(
                treatment: .gameBoyWars2,
                titleFont: themedFont(18, relativeTo: .title2, weight: .bold),
                titleColor: Self.rgb555(0, 1, 4),
                surface: Self.rgb555(29, 31, 31),
                secondarySurface: Self.rgb555(18, 27, 31),
                border: Self.rgb555(0, 1, 4),
                innerBorder: Self.rgb555(3, 13, 31),
                shadow: Self.rgb555(0, 1, 4),
                cornerRadius: 0,
                borderPixels: 1,
                shadowRadius: 0,
                shadowYOffset: 1
            )
        case .gameBoyWars3:
            PlaytestBannerTheme(
                treatment: .gameBoyWars3,
                titleFont: themedFont(18, relativeTo: .title2, weight: .bold),
                titleColor: Self.rgb555(31, 24, 0),
                surface: Self.rgb(0x000000),
                secondarySurface: Self.rgb555(0, 11, 29),
                border: Self.rgb555(0, 26, 31),
                innerBorder: Self.rgb555(0, 12, 29),
                shadow: Self.rgb555(0, 3, 8),
                cornerRadius: 8,
                borderPixels: 2,
                shadowRadius: 0,
                shadowYOffset: 1
            )
        case .advanceWars:
            PlaytestBannerTheme(
                treatment: .advanceWars,
                titleFont: themedFont(23, relativeTo: .title2, weight: .regular),
                titleColor: Self.rgb555(31, 31, 29),
                surface: Self.rgb555(2, 5, 10),
                secondarySurface: Self.rgb555(4, 12, 20),
                border: .clear,
                innerBorder: .clear,
                shadow: .clear,
                cornerRadius: 0,
                borderPixels: 0,
                shadowRadius: 0,
                shadowYOffset: 0
            )
        case .advanceWars2:
            PlaytestBannerTheme(
                treatment: .advanceWars2,
                titleFont: themedFont(23, relativeTo: .title2, weight: .regular),
                titleColor: Self.rgb555(31, 31, 29),
                surface: Self.rgb555(3, 8, 16),
                secondarySurface: Self.rgb555(5, 17, 29),
                border: .clear,
                innerBorder: .clear,
                shadow: .clear,
                cornerRadius: 0,
                borderPixels: 0,
                shadowRadius: 0,
                shadowYOffset: 0
            )
        case .dualStrike:
            PlaytestBannerTheme(
                treatment: .dualStrike,
                titleFont: .custom("Silkscreen", size: 22, relativeTo: .title2).weight(.bold),
                titleColor: .clear,
                surface: .clear,
                secondarySurface: .clear,
                border: .clear,
                innerBorder: .clear,
                shadow: .clear,
                cornerRadius: 0,
                borderPixels: 0,
                shadowRadius: 0,
                shadowYOffset: 0
            )
        case .daysOfRuin:
            PlaytestBannerTheme(
                treatment: .daysOfRuin,
                titleFont: themedFont(26, relativeTo: .title, weight: .bold),
                titleColor: Self.rgb555(31, 31, 29),
                surface: Self.rgb555(4, 9, 11),
                secondarySurface: Self.rgb555(8, 16, 18),
                border: Self.rgb555(19, 27, 29),
                innerBorder: Self.rgb555(9, 20, 22),
                shadow: Self.rgb555(1, 2, 3),
                cornerRadius: 1,
                borderPixels: 1,
                shadowRadius: 3,
                shadowYOffset: 2
            )
        }
    }

}
