import AWEDCore
import SwiftUI

extension PlaytestStatusTheme {
    // These values describe the games' compact map/status popups, rather than
    // borrowing the more decorative chrome from their title and CO screens.
    var surface: Color {
        switch self {
        case .famicomWars:
            FamicomPPUPalette.black
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
            FamicomPPUPalette.white
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
            FamicomPPUPalette.gray
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
        case .famicomWars: FamicomPPUPalette.darkGray
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
        case .famicomWars: FamicomPPUPalette.white
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
        case .famicomWars: 2
        case .advanceWars, .advanceWars2, .dualStrike: 0
        default: 1
        }
    }

    var innerBorderPixels: CGFloat {
        switch self {
        case .famicomWars: 2
        case .gameBoyWars, .superFamicomWars, .gameBoyWars2, .gameBoyWars3: 1
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin: 0
        }
    }

    var innerBorderInsetPixels: CGFloat {
        switch self {
        case .famicomWars: 2
        case .superFamicomWars, .gameBoyWars3: 3
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
        case .famicomWars, .gameBoyWars, .superFamicomWars, .gameBoyWars2, .gameBoyWars3: 6
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin: 8
        }
    }

    var preferredColorScheme: ColorScheme {
        switch self {
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3: .light
        default: .dark
        }
    }

}
