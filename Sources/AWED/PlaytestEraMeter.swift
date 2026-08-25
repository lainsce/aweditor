import SwiftUI

struct PlaytestEraMeter: View {
    let value: Double
    let total: Double
    let tint: Color
    let theme: PlaytestStatusTheme

    @Environment(\.displayScale) private var displayScale

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(min(max(value / total, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let pixel = 1 / max(displayScale, 1)
            let shape = RoundedRectangle(cornerRadius: theme.meterCornerRadius)

            ZStack(alignment: .leading) {
                shape.fill(theme.meterTrack)

                shape
                    .fill(tint)
                    .frame(width: proxy.size.width * fraction)
                    .clipShape(shape)

                HStack(spacing: 0) {
                    ForEach(1..<theme.meterSegmentCount, id: \.self) { _ in
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(theme.meterDivider)
                            .frame(width: pixel)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, pixel)
                .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(
                    theme.meterBorder,
                    style: StrokeStyle(lineWidth: pixel),
                    antialiased: false
                )
                .allowsHitTesting(false)
            }
        }
        .frame(height: theme.meterHeight)
        .accessibilityHidden(true)
    }
}
