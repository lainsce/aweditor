import SwiftUI
import AWEDCore

extension PlaytestDayBanner {
    @ViewBuilder
    var surfaceTreatment: some View {
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
    var edgeTreatment: some View {
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

    var gbWars3FactionName: String {
        army == AWConstants.armyBlueMoon ? "WHITE MOON" : "RED STAR"
    }

    var gbWars3DayText: String {
        String(format: "%02d", max(0, day))
    }

    @ViewBuilder
    var titleContent: some View {
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

    var advanceWarsBannerFont: Font {
        .custom(
            "Share Tech Mono",
            size: min(72, max(38, bannerHeight * 0.74)),
            relativeTo: .largeTitle
        )
        .weight(.bold)
    }

    @ViewBuilder
    var innerFrame: some View {
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

        return ZStack {
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
