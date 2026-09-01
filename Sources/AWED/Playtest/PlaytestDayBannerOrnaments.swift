import AppKit
import SwiftUI
import AWEDCore


struct PlaytestSuperFamicomWarsBannerOrnament: View {
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
