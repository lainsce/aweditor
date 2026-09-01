import AppKit
import SwiftUI
import AWEDCore


struct PlaytestOutlinedBannerText: View {
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

struct PlaytestDualStrikeEmblem: View {
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

struct PlaytestStarShape: Shape {
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
struct PlaytestDualStrikeCrescentShape: Shape {
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
struct PlaytestDualStrikeCometShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let points = [
            CGPoint(x: width * 0.01, y: height * 0.44),
            CGPoint(x: width * 0.15, y: height * 0.55),
            CGPoint(x: width * 0.98, y: height * 0.01),
            CGPoint(x: width * 0.47, y: height * 0.84),
            CGPoint(x: width * 0.55, y: height * 0.98),
            CGPoint(x: width * 0.01, y: height * 0.98)
        ]
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// Dual Strike's Black Hole emblem is the four-part angular mark in a white
/// square.  The four independent trapezoids leave the same off-centre cross
/// of white space as the original icon; it is intentionally not the spiral
/// approximation that was previously used by the banner.
struct PlaytestDualStrikeBlackHoleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let scale: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: width * x, y: height * y)
        }
        let arms: [[(CGFloat, CGFloat)]] = [
            [(0.06, 0.06), (0.66, 0.06), (0.66, 0.46), (0.40, 0.46)],
            [(0.76, 0.46), (0.96, 0.10), (0.96, 0.66), (0.76, 0.66)],
            [(0.04, 0.55), (0.42, 0.55), (0.42, 0.78), (0.04, 0.94)],
            [(0.52, 0.78), (0.76, 0.78), (0.94, 0.94), (0.52, 0.94)]
        ]
        var path = Path()
        for arm in arms {
            path.addLines(arm.map(scale))
            path.closeSubpath()
        }
        return path
    }
}
