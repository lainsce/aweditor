import AppKit
import SwiftUI
import AWEDCore


struct PlaytestRetroDayReadout: View {
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
struct PlaytestSuperFamicomWarsDayReadout: View {
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
