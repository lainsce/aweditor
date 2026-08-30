import AWEDCore
import SwiftUI

extension PlaytestFrameTheme {
    static let famicomWars = PlaytestFrameTheme(
        parchmentGradient: [FamicomPPUPalette.black, FamicomPPUPalette.black, FamicomPPUPalette.black],
        parchmentHighlight: FamicomPPUPalette.black,
        parchmentShadow: FamicomPPUPalette.black,
        gridColor: FamicomPPUPalette.black,
        gridRegularOpacity: 0,
        gridMajorOpacity: 0,
        flatWoodBorderStyle: .inspector(.famicomWars),
        woodGradient: [FamicomPPUPalette.brown, FamicomPPUPalette.darkBrown, FamicomPPUPalette.gold],
        woodLowerBase: nil,
        woodDeep: FamicomPPUPalette.black,
        woodHighlight: FamicomPPUPalette.yellow,
        woodGrainDark: FamicomPPUPalette.brown,
        woodGrainLight: FamicomPPUPalette.gold,
        headerTint: FamicomPPUPalette.black,
        headerFGTint: FamicomPPUPalette.white,
        headerOpacity: 1,
        headerBorder: FamicomPPUPalette.darkGray,
        headerShadow: FamicomPPUPalette.black
    )
}
