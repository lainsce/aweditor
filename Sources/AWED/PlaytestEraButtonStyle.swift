import SwiftUI

struct PlaytestEraButtonStyle: ButtonStyle {
    enum Tone {
        case primary
        case neutral
    }

    let theme: PlaytestStatusTheme
    let tone: Tone

    @Environment(\.displayScale) private var displayScale
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pixel = 1 / max(displayScale, 1)
        let shape = RoundedRectangle(cornerRadius: theme.buttonCornerRadius)

        configuration.label
            .font(theme.detailFont)
            .lineLimit(1)
            .foregroundStyle(theme.buttonText(tone: tone))
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: theme.buttonMinHeight)
            .background {
                shape.fill(theme.buttonSurface(tone: tone, pressed: configuration.isPressed))
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(theme.buttonUpperEdge.opacity(configuration.isPressed ? 0.24 : 0.86))
                    .frame(height: pixel)
                    .padding(.horizontal, pixel)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.buttonLowerEdge)
                    .frame(height: configuration.isPressed ? pixel : 2 * pixel)
                    .padding(.horizontal, pixel)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(
                    theme.buttonBorder,
                    style: StrokeStyle(lineWidth: pixel),
                    antialiased: false
                )
                .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.42)
            .offset(y: configuration.isPressed ? pixel : 0)
            .contentShape(shape)
    }
}
