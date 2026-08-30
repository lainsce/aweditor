import AppKit
import SwiftUI
import AWEDCore

struct PlaytestMapColumn: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let atlas: SpriteAtlas
    let mapSize: CGSize

    var body: some View {
        PlaytestMapSurface(
            session: session,
            previewModel: previewModel,
            atlas: atlas,
            mapSize: mapSize
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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

    @Environment(\.displayScale) private var displayScale

    private var statusTheme: PlaytestStatusTheme {
        PlaytestStatusTheme(tileset: tileset)
    }

    private var bannerTheme: PlaytestBannerTheme {
        statusTheme.bannerTheme
    }

    private var dualStrikeCircleDiameter: CGFloat {
        max(172, bannerHeight * 1.34)
    }

    private var armyColor: Color {
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

    @ViewBuilder
    private var surfaceTreatment: some View {
        switch bannerTheme.treatment {
        case .famicomWars:
            bannerTheme.surface

        case .gameBoyWars:
            bannerTheme.surface

        case .superFamicomWars:
            LinearGradient(
                colors: [
                    bannerTheme.secondarySurface.opacity(0.94),
                    bannerTheme.surface,
                    bannerTheme.secondarySurface.opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

        case .gameBoyWars2:
            ZStack {
                bannerTheme.surface
                Rectangle()
                    .fill(armyColor.opacity(0.72))
                    .frame(width: 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .gameBoyWars3:
            ZStack {
                bannerTheme.surface
                bannerTheme.secondarySurface.opacity(0.16)
            }

        case .advanceWars:
            ZStack {
                Color.black.opacity(0.48)
                LinearGradient(
                    colors: [
                        armyColor.opacity(0.52),
                        Color.black.opacity(0.62),
                        armyColor.opacity(0.52)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

        case .advanceWars2:
            ZStack {
                Color.black.opacity(0.42)
                LinearGradient(
                    colors: [
                        armyColor.opacity(0.42),
                        Color.black.opacity(0.62),
                        armyColor.opacity(0.42)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }

        case .dualStrike:
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: dualStrikeCircleDiameter, height: dualStrikeCircleDiameter)
                    .overlay {
                        Circle()
                            .stroke(armyColor.opacity(0.80), lineWidth: 7)
                    }
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.62), lineWidth: 2)
                            .padding(9)
                    }
            }

        case .daysOfRuin:
            ZStack {
                bannerTheme.surface
                bannerTheme.secondarySurface.opacity(0.34)
                Rectangle()
                    .fill(bannerTheme.innerBorder.opacity(0.54))
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    @ViewBuilder
    private var edgeTreatment: some View {
        switch bannerTheme.treatment {
        case .famicomWars:
            Color.clear.frame(height: 0)

        case .gameBoyWars:
            Rectangle()
                .fill(bannerTheme.innerBorder)
                .frame(height: 2)

        case .superFamicomWars:
            ZStack {
                bannerTheme.border
                Rectangle()
                    .fill(bannerTheme.innerBorder)
                    .frame(height: 9)
                Rectangle()
                    .fill(Color.white.opacity(0.48))
                    .frame(height: 2)
                    .offset(y: -3)
                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .frame(height: 2)
                    .offset(y: 3)
            }
            .frame(height: 16)

        case .gameBoyWars2:
            Rectangle()
                .fill(bannerTheme.innerBorder)
                .frame(height: 1)

        case .gameBoyWars3:
            Color.clear.frame(height: 0)

        case .advanceWars, .advanceWars2:
            Color.clear.frame(height: 0)

        case .dualStrike:
            Color.clear.frame(height: 0)

        case .daysOfRuin:
            HStack(spacing: 3) {
                ForEach(0..<14, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? bannerTheme.innerBorder : bannerTheme.border)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 5)
        }
    }

    private var gbWars3FactionName: String {
        army == AWConstants.armyBlueMoon ? "WHITE MOON" : "RED STAR"
    }

    private var gbWars3DayText: String {
        String(format: "%02d", max(0, day))
    }

    @ViewBuilder
    private var titleContent: some View {
        if bannerTheme.treatment == .dualStrike {
            VStack(spacing: bannerHeight > Self.height ? 4 : -7) {
                Text("DAY \(day)")
                    .font(
                        .custom(
                            "Silkscreen",
                            size: min(112, max(22, bannerHeight * 0.18)),
                            relativeTo: .largeTitle
                        )
                        .weight(.bold)
                    )
                    .foregroundStyle(armyColor)
                    .tracking(1.5)
                    .lineLimit(1)
                PlaytestDualStrikeEmblem(
                    army: army,
                    color: armyColor,
                    size: min(220, max(25, bannerHeight * 0.30))
                )
            }
        } else if bannerTheme.treatment == .advanceWars {
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                PlaytestOutlinedBannerText(
                    text: "DAY",
                    font: advanceWarsBannerFont,
                    fill: Color(red: 1.0, green: 0.66, blue: 0.02),
                    outline: Color.black,
                    outlineWidth: 3
                )
                PlaytestOutlinedBannerText(
                    text: String(max(0, day)),
                    font: advanceWarsBannerFont,
                    fill: Color.white,
                    outline: Color.black,
                    outlineWidth: 3
                )
            }
        } else if bannerTheme.treatment == .advanceWars2 {
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                PlaytestOutlinedBannerText(
                    text: "DAY",
                    font: advanceWarsBannerFont,
                    fill: Color.white,
                    outline: Color.black,
                    outlineWidth: 3
                )
                PlaytestOutlinedBannerText(
                    text: String(max(0, day)),
                    font: advanceWarsBannerFont,
                    fill: Color.white,
                    outline: armyColor,
                    outlineWidth: 3
                )
                .shadow(color: Color.black.opacity(0.90), radius: 0, x: 4, y: 4)
            }
        } else if bannerTheme.treatment == .gameBoyWars3 {
            HStack(spacing: 13) {
                ZStack {
                    Rectangle()
                        .fill(
                            army == AWConstants.armyBlueMoon
                                ? Color(red: 0.04, green: 0.22, blue: 0.78)
                                : Color(red: 0.78, green: 0.08, blue: 0.04)
                        )

                    if army == AWConstants.armyBlueMoon {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 31, height: 31)
                        Circle()
                            .fill(Color(red: 0.04, green: 0.22, blue: 0.78))
                            .frame(width: 27, height: 27)
                            .offset(x: 8, y: -5)
                    } else {
                        Text("★")
                            .font(.system(size: 30, weight: .black))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 50, height: 45)
                .overlay {
                    Rectangle()
                        .strokeBorder(
                            bannerTheme.innerBorder,
                            style: StrokeStyle(lineWidth: 1 / max(displayScale, 1)),
                            antialiased: false
                        )
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(gbWars3FactionName)
                        .font(.custom("Silkscreen", size: 13, relativeTo: .headline).weight(.bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(gbWars3DayText)
                            .font(.custom("Silkscreen", size: 34, relativeTo: .largeTitle).weight(.bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.02))
                            .lineLimit(1)
                        Text("DAYS")
                            .font(.custom("Silkscreen", size: 13, relativeTo: .headline).weight(.bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.02))
                    }
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 18)
        } else if bannerTheme.treatment == .famicomWars {
            PlaytestRetroDayReadout(
                day: day,
                treatment: .famicomWars,
                theme: bannerTheme
            )
        } else if bannerTheme.treatment == .superFamicomWars {
            PlaytestSuperFamicomWarsDayReadout(
                day: day,
                army: army,
                atlas: atlas,
                bannerHeight: bannerHeight,
                textColor: bannerTheme.titleColor,
                ornamentColor: armyColor
            )
        } else if bannerTheme.treatment == .gameBoyWars {
            PlaytestRetroDayReadout(
                day: day,
                treatment: .gameBoyWars,
                theme: bannerTheme
            )
        } else if bannerTheme.treatment == .gameBoyWars2 {
            PlaytestRetroDayReadout(
                day: day,
                treatment: .gameBoyWars2,
                theme: bannerTheme
            )
        } else if bannerTheme.treatment == .daysOfRuin {
            PlaytestRetroDayReadout(
                day: day,
                treatment: .daysOfRuin,
                theme: bannerTheme
            )
        } else {
            Text("DAY \(day)")
                .font(bannerTheme.titleFont)
                .foregroundStyle(bannerTheme.titleColor)
                .tracking(bannerTheme.treatment == .dualStrike ? 1.5 : 0)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var advanceWarsBannerFont: Font {
        .custom(
            "Share Tech Mono",
            size: min(72, max(38, bannerHeight * 0.74)),
            relativeTo: .largeTitle
        )
        .weight(.bold)
    }

    @ViewBuilder
    private var innerFrame: some View {
        switch bannerTheme.treatment {
        case .famicomWars:
            Color.clear.frame(height: 0)
        case .gameBoyWars, .gameBoyWars2:
            RoundedRectangle(cornerRadius: 0)
                .inset(by: 3 / max(displayScale, 1))
                .strokeBorder(
                    bannerTheme.innerBorder,
                    style: StrokeStyle(lineWidth: 1 / max(displayScale, 1)),
                    antialiased: false
                )
        case .gameBoyWars3:
            RoundedRectangle(cornerRadius: bannerTheme.cornerRadius)
                .inset(by: 3 / max(displayScale, 1))
                .strokeBorder(
                    bannerTheme.innerBorder,
                    style: StrokeStyle(lineWidth: 1 / max(displayScale, 1)),
                    antialiased: false
                )
        case .superFamicomWars:
            Color.clear.frame(height: 0)
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin:
            RoundedRectangle(cornerRadius: bannerTheme.cornerRadius)
                .inset(by: 2 / max(displayScale, 1))
                .strokeBorder(
                    bannerTheme.innerBorder.opacity(0.72),
                    style: StrokeStyle(lineWidth: 1 / max(displayScale, 1)),
                    antialiased: false
                )
        }
    }

    var body: some View {
        let pixel = 1 / max(displayScale, 1)
        let shape = RoundedRectangle(cornerRadius: bannerTheme.cornerRadius)

        ZStack {
            surfaceTreatment

            titleContent
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.40), value: day)
        }
        .frame(maxWidth: .infinity, minHeight: bannerHeight, maxHeight: bannerHeight)
        .clipShape(shape)
        .overlay(alignment: .top) { edgeTreatment }
        .overlay(alignment: .bottom) { edgeTreatment }
        .overlay {
            if bannerTheme.treatment == .famicomWars {
                // The original Famicom plate leaves a black two-pixel margin
                // outside its green rule. Inset the green stroke so the
                // surrounding map cannot touch it at the banner edge.
                ZStack {
                    shape.strokeBorder(
                        FamicomPPUPalette.black,
                        style: StrokeStyle(lineWidth: 2 * pixel),
                        antialiased: false
                    )
                    shape
                        .inset(by: 2 * pixel)
                        .strokeBorder(
                            bannerTheme.border,
                            style: StrokeStyle(lineWidth: bannerTheme.borderPixels * pixel),
                            antialiased: false
                        )
                    shape
                        .inset(by: 4 * pixel)
                        .strokeBorder(
                            FamicomPPUPalette.black,
                            style: StrokeStyle(lineWidth: pixel),
                            antialiased: false
                        )
                }
            } else {
                shape.strokeBorder(
                    bannerTheme.border,
                    style: StrokeStyle(lineWidth: bannerTheme.borderPixels * pixel),
                    antialiased: false
                )
            }
        }
        .overlay { innerFrame }
        .shadow(
            color: bannerTheme.shadow.opacity(0.72),
            radius: bannerTheme.shadowRadius,
            y: bannerTheme.shadowYOffset
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day \(day)")
    }
}

private struct PlaytestRetroDayReadout: View {
    let day: Int
    let treatment: PlaytestBannerTreatment
    let theme: PlaytestBannerTheme

    private var dayNumber: String {
        String(max(0, day))
    }

    private var twoDigitDay: String {
        String(format: "%02d", max(0, day))
    }

    @ViewBuilder
    var body: some View {
        switch treatment {
        case .famicomWars:
            Text("Day \(dayNumber)")
                .font(.custom("Press Start 2P", size: 16, relativeTo: .caption))
                .foregroundStyle(theme.titleColor)
                .lineLimit(1)

        case .superFamicomWars:
            Text("D\(twoDigitDay)")
                .font(.custom("VT323", size: 29, relativeTo: .largeTitle))
                .foregroundStyle(theme.titleColor)
                .tracking(1)

        case .gameBoyWars:
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("DAY")
                    .font(.custom("VT323", size: 25, relativeTo: .headline))
                    .foregroundStyle(theme.innerBorder)
                Text(dayNumber)
                    .font(.custom("VT323", size: 38, relativeTo: .largeTitle))
                    .foregroundStyle(theme.titleColor)
            }

        case .gameBoyWars2:
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("DAY")
                    .font(.custom("Silkscreen", size: 13, relativeTo: .headline).weight(.bold))
                    .foregroundStyle(theme.innerBorder)
                Text(dayNumber)
                    .font(.custom("Silkscreen", size: 27, relativeTo: .largeTitle).weight(.bold))
                    .foregroundStyle(theme.titleColor)
            }

        case .daysOfRuin:
            VStack(alignment: .leading, spacing: -8) {
                Text(dayNumber)
                    .font(.custom("Share Tech Mono", size: 40, relativeTo: .largeTitle).weight(.bold))
                    .foregroundStyle(theme.titleColor)
                    .minimumScaleFactor(0.72)
                Text("Day")
                    .font(.custom("Share Tech Mono", size: 13, relativeTo: .caption).weight(.bold))
                    .foregroundStyle(theme.secondarySurface.opacity(0.92))
            }
            .padding(.horizontal, 16)

        default:
            Text("DAY \(dayNumber)")
                .font(theme.titleFont)
                .foregroundStyle(theme.titleColor)
        }
    }
}

private struct PlaytestSuperFamicomWarsDayReadout: View {
    let day: Int
    let army: Int
    let atlas: SpriteAtlas
    let bannerHeight: CGFloat
    let textColor: Color
    let ornamentColor: Color

    private var headingFont: Font {
        .custom(
            "Silkscreen",
            size: min(52, max(24, bannerHeight * 0.25)),
            relativeTo: .title
        )
        .weight(.bold)
    }

    private var dayFont: Font {
        .custom(
            "Silkscreen",
            size: min(68, max(34, bannerHeight * 0.34)),
            relativeTo: .largeTitle
        )
        .weight(.bold)
    }

    var body: some View {
        ZStack {
            HStack {
                PlaytestSuperFamicomWarsBannerOrnament(
                    army: army,
                    atlas: atlas,
                    color: ornamentColor,
                    mirrored: false
                )
                Spacer(minLength: 0)
                PlaytestSuperFamicomWarsBannerOrnament(
                    army: army,
                    atlas: atlas,
                    color: ornamentColor,
                    mirrored: true
                )
            }
            .padding(.horizontal, 58)
            .padding(.top, 10)

            VStack(spacing: -4) {
                PlaytestOutlinedBannerText(
                    text: "IT'S DAY",
                    font: headingFont,
                    fill: textColor,
                    outline: Color(red: 0.16, green: 0.09, blue: 0.13),
                    outlineWidth: 2
                )
                .tracking(1)

                Text(String(max(0, day)))
                    .font(dayFont)
                    .foregroundStyle(Color.white)
                    .shadow(
                        color: Color(red: 0.16, green: 0.09, blue: 0.13),
                        radius: 0,
                        x: 2,
                        y: 2
                    )
                    .lineLimit(1)
            }
        }
        .padding(.top, 8)
    }
}

private struct PlaytestSuperFamicomWarsBannerOrnament: View {
    let army: Int
    let atlas: SpriteAtlas
    let color: Color
    let mirrored: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.65, green: 0.42, blue: 0.23))
                .frame(width: 4, height: 108)
                .offset(x: 12, y: 4)

            Circle()
                .fill(Color(red: 0.82, green: 0.60, blue: 0.34))
                .frame(width: 8, height: 8)
                .offset(x: 10, y: 0)

            PlaytestSuperFamicomWarsBannerFlag(color: color)
                .frame(width: 52, height: 29)
                .offset(x: 16, y: 5)

            if let image = atlas.image(
                for: Element.unitInfantry.changedArmy(army),
                palette: .superFamicomWars
            ) {
                image
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 62, height: 62)
                    .offset(x: 1, y: 52)
            }
        }
        .frame(width: 82, height: 118)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .accessibilityHidden(true)
    }
}

private struct PlaytestSuperFamicomWarsBannerFlag: View {
    let color: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [color, color.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(spacing: 2) {
                Rectangle()
                    .fill(Color.white.opacity(0.66))
                    .frame(width: 4, height: 20)
                PlaytestStarShape()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 18, height: 18)
                Rectangle()
                    .fill(Color.white.opacity(0.66))
                    .frame(width: 4, height: 20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.black.opacity(0.76), lineWidth: 2)
        }
    }
}

private struct PlaytestOutlinedBannerText: View {
    let text: String
    let font: Font
    let fill: Color
    let outline: Color
    let outlineWidth: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) * Double.pi / 4
                Text(text)
                    .font(font)
                    .foregroundStyle(outline)
                    .offset(
                        x: CGFloat(cos(angle)) * outlineWidth,
                        y: CGFloat(sin(angle)) * outlineWidth
                    )
            }

            Text(text)
                .font(font)
                .foregroundStyle(fill)
        }
        .fixedSize()
    }
}

private struct PlaytestDualStrikeEmblem: View {
    let army: Int
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            // Dual Strike uses a shared faction-badge construction: a
            // colour-matched rounded frame around a white square, with the
            // faction mark cut into that square.  Keeping the badge here (as
            // opposed to drawing a free-floating glyph) makes the playtest
            // banner match the emblems used by the cartridge UI.
            RoundedRectangle(cornerRadius: size * 0.056, style: .continuous)
                .fill(color)

            Rectangle()
                .fill(Color.white)
                .padding(size * 0.068)

            symbol
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var symbol: some View {
        switch army {
        case AWConstants.armyOrangeStar:
            PlaytestStarShape()
                .fill(color)

        case AWConstants.armyBlueMoon:
            PlaytestDualStrikeCrescentShape()
                .fill(color, style: FillStyle(eoFill: true))

        case AWConstants.armyGreenEarth:
            Circle()
                .fill(color)

        case AWConstants.armyYellowComet:
            PlaytestDualStrikeCometShape()
                .fill(color)

        case AWConstants.armyBlackHole:
            PlaytestDualStrikeBlackHoleShape()
                .fill(color)

        default:
            Circle()
                .fill(color)
        }
    }
}

private struct PlaytestStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) * 0.5
        let innerRadius = outerRadius * 0.43
        var path = Path()

        for index in 0..<10 {
            let angle = -Double.pi / 2 + (Double(index) * Double.pi / 5)
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()
        return path
    }
}

/// The Dual Strike Blue Moon badge uses a broad, left-heavy crescent.  Keep
/// the cutout inside the outer disk so even-odd filling cannot leak a second
/// crescent outside the white badge field.
private struct PlaytestDualStrikeCrescentShape: Shape {
    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        let origin = CGPoint(
            x: rect.midX - diameter / 2,
            y: rect.midY - diameter / 2
        )
        let outer = CGRect(
            origin: origin,
            size: CGSize(width: diameter, height: diameter)
        )
        let inner = outer
            .insetBy(dx: diameter * 0.18, dy: diameter * 0.18)
            .offsetBy(dx: diameter * 0.16, dy: -diameter * 0.08)

        var path = Path()
        path.addEllipse(in: outer)
        path.addEllipse(in: inner)
        return path
    }
}

/// The Yellow Comet mark in Dual Strike is a deliberately angular wedge,
/// rather than a curved comet or a generic star.  These normalized points
/// follow the six-corner silhouette of the original badge.
private struct PlaytestDualStrikeCometShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        path.move(to: CGPoint(x: width * 0.01, y: height * 0.44))
        path.addLine(to: CGPoint(x: width * 0.15, y: height * 0.55))
        path.addLine(to: CGPoint(x: width * 0.98, y: height * 0.01))
        path.addLine(to: CGPoint(x: width * 0.47, y: height * 0.84))
        path.addLine(to: CGPoint(x: width * 0.55, y: height * 0.98))
        path.addLine(to: CGPoint(x: width * 0.01, y: height * 0.98))
        path.closeSubpath()
        return path
    }
}

/// Dual Strike's Black Hole emblem is the four-part angular mark in a white
/// square.  The four independent trapezoids leave the same off-centre cross
/// of white space as the original icon; it is intentionally not the spiral
/// approximation that was previously used by the banner.
private struct PlaytestDualStrikeBlackHoleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        // Upper-left arm.
        path.move(to: CGPoint(x: width * 0.06, y: height * 0.06))
        path.addLine(to: CGPoint(x: width * 0.66, y: height * 0.06))
        path.addLine(to: CGPoint(x: width * 0.66, y: height * 0.46))
        path.addLine(to: CGPoint(x: width * 0.40, y: height * 0.46))
        path.closeSubpath()

        // Upper-right arm.
        path.move(to: CGPoint(x: width * 0.76, y: height * 0.46))
        path.addLine(to: CGPoint(x: width * 0.96, y: height * 0.10))
        path.addLine(to: CGPoint(x: width * 0.96, y: height * 0.66))
        path.addLine(to: CGPoint(x: width * 0.76, y: height * 0.66))
        path.closeSubpath()

        // Lower-left arm.
        path.move(to: CGPoint(x: width * 0.04, y: height * 0.55))
        path.addLine(to: CGPoint(x: width * 0.42, y: height * 0.55))
        path.addLine(to: CGPoint(x: width * 0.42, y: height * 0.78))
        path.addLine(to: CGPoint(x: width * 0.04, y: height * 0.94))
        path.closeSubpath()

        // Lower-right arm.
        path.move(to: CGPoint(x: width * 0.52, y: height * 0.78))
        path.addLine(to: CGPoint(x: width * 0.76, y: height * 0.78))
        path.addLine(to: CGPoint(x: width * 0.94, y: height * 0.94))
        path.addLine(to: CGPoint(x: width * 0.52, y: height * 0.94))
        path.closeSubpath()

        return path
    }
}

private struct PlaytestMapSurface: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let atlas: SpriteAtlas
    let mapSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedCameraFocusPoint: GridPoint?

    private static let cameraStepNanoseconds: UInt64 = 55_000_000

    /// The playtest map is a camera viewport rather than a document canvas.
    /// Follow the most immediate point of activity first, then fall back to
    /// the cartridge cursor or the current selection when an action is idle.
    private var cameraFocusPoint: GridPoint? {
        session.cpuMovementPath.last
            // During a legacy CPU turn the cartridge cursor is the actual
            // point of action. Prefer it once a stepped route has finished so
            // clearing the render-only path cannot snap the camera back to the
            // movement origin.
            ?? (session.activeArmyIsCPU && session.ruleset.usesLegacyKeyboardControls ? session.cursorPoint : nil)
            ?? (session.activeArmyIsCPU ? session.cpuActionPoint : nil)
            ?? (session.activeArmyIsCPU ? session.selectedPoint : nil)
            ?? session.playerMovementPath.last
            ?? previewModel.pointerCell
            // AWDS/AWDR use pointer interaction and do not render the
            // cartridge cursor. Do not let the legacy cursor's first-unit
            // fallback pan those maps away from their centered initial view.
            ?? (session.ruleset.usesLegacyKeyboardControls ? session.cursorPoint : nil)
            ?? session.selectedPoint
    }

    var body: some View {
        let tileSize = MapCanvasMetrics.tileSize
        let frameTheme = PlaytestFrameTheme.playtest(for: session.map.tileset)
        let woodPadding = MapCanvasMetrics.woodPadding(for: frameTheme)
        let boardSize = CGSize(
            width: mapSize.width + (woodPadding * 2),
            height: mapSize.height + (woodPadding * 2) + MapCanvasMetrics.bottomWallHeight(for: frameTheme)
        )
        let minimumContentSize = CGSize(
            width: boardSize.width + (MapCanvasMetrics.parchmentPadding * 2),
            height: boardSize.height + (MapCanvasMetrics.parchmentPadding * 2)
        )

        GeometryReader { proxy in
            let contentSize = CGSize(
                width: max(proxy.size.width, minimumContentSize.width),
                height: max(proxy.size.height, minimumContentSize.height)
            )
            let boardOrigin = CGPoint(
                x: (contentSize.width - minimumContentSize.width) / 2,
                y: (contentSize.height - minimumContentSize.height) / 2
            )

            let cameraOffset = cameraOffset(
                viewportSize: proxy.size,
                contentSize: contentSize,
                boardOrigin: boardOrigin,
                woodPadding: woodPadding,
                focusPoint: displayedCameraFocusPoint ?? cameraFocusPoint
            )

            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: proxy.size.width, height: proxy.size.height)

                ZStack(alignment: .topLeading) {
                    MapCanvasBoard(
                        model: previewModel,
                        atlas: atlas,
                        mapOverride: session.displayMapForPlaytest,
                        interactionEnabled: false,
                        frameTheme: frameTheme
                    )
                        .offset(
                            x: boardOrigin.x + MapCanvasMetrics.parchmentPadding,
                            y: boardOrigin.y + MapCanvasMetrics.parchmentPadding
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    PlaytestWeatherOverlay(
                        weather: session.weather,
                        mapSize: mapSize
                    )
                        .frame(width: mapSize.width, height: mapSize.height)
                        .offset(
                            x: boardOrigin.x + MapCanvasMetrics.parchmentPadding + woodPadding,
                            y: boardOrigin.y + MapCanvasMetrics.parchmentPadding + woodPadding
                        )

                    PlaytestInteractionLayer(
                        session: session,
                        previewModel: previewModel,
                        atlas: atlas,
                        tileSize: tileSize
                    )
                        .frame(width: mapSize.width, height: mapSize.height)
                        .offset(
                            x: boardOrigin.x + MapCanvasMetrics.parchmentPadding + woodPadding,
                            y: boardOrigin.y + MapCanvasMetrics.parchmentPadding + woodPadding
                        )
                }
                .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
                .offset(cameraOffset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .task(id: cameraFocusPoint) {
            await advanceCamera(to: cameraFocusPoint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Move the camera target through the grid one cardinal cell at a time.
    /// This keeps a long cursor jump or a CPU action from cutting directly to
    /// the endpoint, while the map itself remains a clipped, non-scrollable
    /// viewport.
    @MainActor
    private func advanceCamera(to target: GridPoint?) async {
        guard !Task.isCancelled else { return }
        guard let target else {
            displayedCameraFocusPoint = nil
            return
        }

        guard var current = displayedCameraFocusPoint else {
            displayedCameraFocusPoint = target
            return
        }
        guard current != target else { return }

        while current != target {
            guard !Task.isCancelled else { return }
            if current.x != target.x {
                current = GridPoint(
                    x: current.x + (target.x > current.x ? 1 : -1),
                    y: current.y
                )
            } else {
                current = GridPoint(
                    x: current.x,
                    y: current.y + (target.y > current.y ? 1 : -1)
                )
            }
            displayedCameraFocusPoint = current
            guard !reduceMotion else { continue }
            try? await Task.sleep(nanoseconds: Self.cameraStepNanoseconds)
        }
    }

    private func cameraOffset(
        viewportSize: CGSize,
        contentSize: CGSize,
        boardOrigin: CGPoint,
        woodPadding: CGFloat,
        focusPoint: GridPoint?
    ) -> CGSize {
        let desired: CGPoint
        if let focusPoint {
            let tileOrigin = MapCanvasMetrics.tileOrigin(
                x: focusPoint.x,
                y: focusPoint.y,
                tileSize: MapCanvasMetrics.tileSize,
                staggered: session.isStaggeredGrid
            )
            let focus = CGPoint(
                x: boardOrigin.x + MapCanvasMetrics.parchmentPadding + woodPadding
                    + tileOrigin.x + (MapCanvasMetrics.tileSize / 2),
                y: boardOrigin.y + MapCanvasMetrics.parchmentPadding + woodPadding
                    + tileOrigin.y + (MapCanvasMetrics.tileSize / 2)
            )
            desired = CGPoint(
                x: (viewportSize.width / 2) - focus.x,
                y: (viewportSize.height / 2) - focus.y
            )
        } else {
            desired = CGPoint(
                x: (viewportSize.width - contentSize.width) / 2,
                y: (viewportSize.height - contentSize.height) / 2
            )
        }

        let minimumX = min(0, viewportSize.width - contentSize.width)
        let minimumY = min(0, viewportSize.height - contentSize.height)
        return CGSize(
            width: min(max(desired.x, minimumX), 0),
            height: min(max(desired.y, minimumY), 0)
        )
    }
}

/// Receives secondary clicks without replacing the SwiftUI primary-tap
/// gesture. The editor uses the same local-monitor approach for its map
/// canvas, which also lets us suppress the default context menu here.
struct PlaytestMapInput: NSViewRepresentable {
    let session: PlaytestSession
    let previewModel: EditorModel
    let tileSize: CGFloat

    func makeNSView(context: Context) -> MonitorView {
        MonitorView(session: session, previewModel: previewModel, tileSize: tileSize)
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.session = session
        nsView.previewModel = previewModel
        nsView.tileSize = tileSize
    }

    @MainActor
    final class MonitorView: NSView {
        var session: PlaytestSession
        var previewModel: EditorModel
        var tileSize: CGFloat
        private var eventMonitor: Any?

        init(session: PlaytestSession, previewModel: EditorModel, tileSize: CGFloat) {
            self.session = session
            self.previewModel = previewModel
            self.tileSize = tileSize
            super.init(frame: .zero)
            wantsLayer = false
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeEventMonitor()
            guard window != nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        isolated deinit { removeEventMonitor() }

        private func removeEventMonitor() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            // Pre-DS cartridges are keyboard-only in playtest. Keep the map
            // monitor alive for the view lifecycle, but do not let a secondary
            // click bypass the A/B/Select command model.
            guard !session.ruleset.usesLegacyKeyboardControls else { return event }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return event }
            guard event.type == .rightMouseDown || event.buttonNumber == 2 else { return event }

            // SwiftUI's interaction layer and the editor both use a top-left
            // origin. Keep secondary-click hit testing in that same coordinate
            // space; inverting Y here made right-click previews select the
            // mirrored row and made the marker appear upside-down.
            let y = Int(floor(location.y / tileSize))
            let rowOffset = session.isStaggeredGrid && y % 2 != 0 ? tileSize / 2 : 0
            let point = GridPoint(
                x: Int(floor((location.x - rowOffset) / tileSize)),
                y: y
            )
            previewModel.updatePointer(point)
            session.handleSecondaryTap(point)
            return nil
        }
    }
}
