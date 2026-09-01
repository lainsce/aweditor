import AppKit
import SwiftUI
import AWEDCore


struct PlaytestDayBanner: View {
    static let height: CGFloat = 64
    static let famicomWarsWidth: CGFloat = 128
    // The original 120×22 plate was sized around an 8 pt readout. Keep its
    // width, but give the current 16 pt Press Start 2P label enough vertical
    // breathing room for the two-pixel border and pixel-clearance margins.
    static let famicomWarsHeight: CGFloat = 32
    static let superFamicomWarsHeight: CGFloat = 184

    let day: Int
    let army: Int
    let tileset: Tileset
    let atlas: SpriteAtlas
    let bannerHeight: CGFloat

    init(
        day: Int,
        army: Int,
        tileset: Tileset,
        atlas: SpriteAtlas,
        bannerHeight: CGFloat? = nil
    ) {
        self.day = day
        self.army = army
        self.tileset = tileset
        self.atlas = atlas
        let treatment = PlaytestStatusTheme(tileset: tileset).bannerTheme.treatment
        let defaultHeight: CGFloat
        switch treatment {
        case .famicomWars:
            defaultHeight = Self.famicomWarsHeight
        case .superFamicomWars:
            defaultHeight = Self.superFamicomWarsHeight
        default:
            defaultHeight = Self.height
        }
        self.bannerHeight = bannerHeight ?? defaultHeight
    }

    static func height(for tileset: Tileset, mapAreaHeight: CGFloat) -> CGFloat {
        let statusTheme = PlaytestStatusTheme(tileset: tileset)
        switch statusTheme.bannerTheme.treatment {
        case .famicomWars:
            return Self.famicomWarsHeight
        case .superFamicomWars:
            // The SNES transition occupies a deep horizontal slice so its
            // two-line title and side ornaments remain legible over the map.
            return min(Self.superFamicomWarsHeight, max(0, mapAreaHeight * 0.42))
        case .dualStrike:
            return max(0, mapAreaHeight)
        default:
            return Self.height
        }
    }

    static func width(
        for tileset: Tileset,
        availableWidth: CGFloat,
        tileSize: CGFloat
    ) -> CGFloat {
        let statusTheme = PlaytestStatusTheme(tileset: tileset)
        if statusTheme.bannerTheme.treatment == .famicomWars {
            return Self.famicomWarsWidth
        }
        guard statusTheme.bannerTheme.treatment == .gameBoyWars3 else {
            return max(0, availableWidth)
        }

        // GB Wars 3 frames the day readout inside the Game Boy map rather
        // than stretching it across the whole screen. Two tiles of breathing
        // room on each side is the physical minimum; the two-thirds cap keeps
        // the plate at roughly the original screen proportion on desktop.
        let twoTileInset = tileSize * 2
        return max(
            0,
            min(availableWidth - (twoTileInset * 2), availableWidth * (2.0 / 3.0))
        )
    }

    @Environment(\.displayScale) var displayScale

    var statusTheme: PlaytestStatusTheme {
        PlaytestStatusTheme(tileset: tileset)
    }

    var bannerTheme: PlaytestBannerTheme {
        statusTheme.bannerTheme
    }

    var dualStrikeCircleDiameter: CGFloat {
        max(172, bannerHeight * 1.34)
    }

    var armyColor: Color {
        if tileset == .daysOfRuin, army == AWConstants.armyBlackHole {
            return Color(white: 0.12)
        }

        if statusTheme == .famicomWars {
            switch army {
            case AWConstants.armyOrangeStar:
                return FamicomPPUPalette.red
            case AWConstants.armyBlueMoon:
                return FamicomPPUPalette.blue
            case AWConstants.armyGreenEarth:
                return FamicomPPUPalette.green
            case AWConstants.armyYellowComet:
                return FamicomPPUPalette.yellow
            case AWConstants.armyBlackHole:
                return FamicomPPUPalette.purple
            default:
                return FamicomPPUPalette.gray
            }
        }

        if statusTheme == .superFamicomWars {
            switch army {
            case AWConstants.armyOrangeStar:
                return Color(red: 0.78, green: 0.20, blue: 0.12)
            case AWConstants.armyBlueMoon:
                return Color(red: 0.24, green: 0.42, blue: 0.76)
            case AWConstants.armyGreenEarth:
                return Color(red: 0.24, green: 0.58, blue: 0.29)
            case AWConstants.armyYellowComet:
                return Color(red: 0.86, green: 0.58, blue: 0.10)
            case AWConstants.armyBlackHole:
                return Color(red: 0.48, green: 0.28, blue: 0.68)
            default:
                break
            }
        }

        if statusTheme == .dualStrike {
            switch army {
            case AWConstants.armyOrangeStar:
                return Color(red: 0.92, green: 0.18, blue: 0.08)
            case AWConstants.armyBlueMoon:
                return Color(red: 0.42, green: 0.18, blue: 0.86)
            case AWConstants.armyGreenEarth:
                return Color(red: 0.10, green: 0.64, blue: 0.46)
            case AWConstants.armyYellowComet:
                return Color(red: 0.95, green: 0.67, blue: 0.08)
            case AWConstants.armyBlackHole:
                return Color(red: 0.63, green: 0.25, blue: 0.78)
            default:
                break
            }
        }

        if tileset.isGameBoyWarsFamily {
            switch army {
            case AWConstants.armyOrangeStar:
                return Color(red: 0.78, green: 0.12, blue: 0.12)
            case AWConstants.armyBlueMoon:
                return Color(white: 0.82)
            default:
                break
            }
        }

        switch army {
        case AWConstants.armyOrangeStar:
            return Color(red: 0.94, green: 0.40, blue: 0.12)
        case AWConstants.armyBlueMoon:
            return Color(red: 0.18, green: 0.47, blue: 0.86)
        case AWConstants.armyGreenEarth:
            return Color(red: 0.22, green: 0.62, blue: 0.27)
        case AWConstants.armyYellowComet:
            return Color(red: 0.92, green: 0.70, blue: 0.08)
        case AWConstants.armyBlackHole:
            return Color(red: 0.48, green: 0.30, blue: 0.72)
        default:
            return .secondary
        }
    }

}
