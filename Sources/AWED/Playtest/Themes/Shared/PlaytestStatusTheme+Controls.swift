import AWEDCore
import SwiftUI

extension PlaytestStatusTheme {
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
        case .famicomWars: FamicomPPUPalette.red
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
        case .famicomWars: FamicomPPUPalette.green
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
        case .famicomWars: FamicomPPUPalette.white
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
        case .famicomWars: FamicomPPUPalette.gray
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
        case .famicomWars: FamicomPPUPalette.darkGray
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
        case (.famicomWars, .primary): FamicomPPUPalette.gray
        case (.famicomWars, .neutral): FamicomPPUPalette.cyan
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
        case .famicomWars: FamicomPPUPalette.black
        case .gameBoyWars: Self.gameBoyLightGray
        case .superFamicomWars: Self.rgb555(8, 3, 5)
        case .gameBoyWars2: Self.rgb555(18, 27, 31)
        case .gameBoyWars3: Self.rgb555(27, 29, 19)
        case .advanceWars, .advanceWars2: Self.rgb555(2, 5, 10)
        case .dualStrike: Self.rgb555(1, 3, 4)
        case .daysOfRuin: Self.rgb555(3, 3, 2)
        }
    }

    /// The original Famicom and first two Game Boy cartridges reported unit
    /// condition as text/icon values rather than drawing a segmented meter.
    /// Keep the theme's meter palette available for shared code, but let the
    /// inspector omit that modern visualization for those eras.
    var showsStatusMeters: Bool {
        switch self {
        case .famicomWars, .superFamicomWars, .gameBoyWars, .gameBoyWars2:
            false
        default:
            true
        }
    }

    var meterBorder: Color { buttonBorder }

    var meterDivider: Color {
        switch self {
        case .famicomWars: FamicomPPUPalette.black
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
            self == .famicomWars ? FamicomPPUPalette.red : Self.rgb555(29, 6, 3)
        case AWConstants.armyBlueMoon:
            self == .famicomWars ? FamicomPPUPalette.blue : Self.rgb555(4, 13, 28)
        case AWConstants.armyGreenEarth:
            self == .famicomWars ? FamicomPPUPalette.green : Self.rgb555(4, 19, 7)
        case AWConstants.armyYellowComet:
            self == .famicomWars ? FamicomPPUPalette.yellow : Self.rgb555(29, 22, 2)
        case AWConstants.armyBlackHole:
            self == .famicomWars ? FamicomPPUPalette.purple : Self.rgb555(12, 7, 18)
        default:
            innerBorder
        }
    }

}
