import AWEDCore
import SwiftUI

extension PlaytestFrameTheme {
    static let superFamicomWars = PlaytestFrameTheme(
        parchmentGradient: [rgb(0xF2E3D0), rgb(0xD9BFA9), rgb(0xB58D78)],
        parchmentHighlight: rgb(0xFFF5E8),
        parchmentShadow: rgb(0x51332A),
        gridColor: rgb(0x6A4338),
        gridRegularOpacity: 0.065,
        gridMajorOpacity: 0.105,
        flatWoodBorderStyle: .inspector(.superFamicomWars),
        woodGradient: [rgb(0x472016), rgb(0x8B4630), rgb(0x542319)],
        woodLowerBase: nil,
        woodDeep: rgb(0x1B0907),
        woodHighlight: rgb(0xD98B57),
        woodGrainDark: rgb(0x2B100B),
        woodGrainLight: rgb(0xE8A47A),
        // Super Famicom Wars keeps the dark brown command-window language
        // in its header rather than switching to the editor's light chrome.
        headerTint: rgb(0x673A2A),
        headerFGTint: rgb(0xFFF5E8),
        headerOpacity: 1,
        headerBorder: rgb(0x1F2730),
        headerShadow: rgb(0x160C0A)
    )
}
