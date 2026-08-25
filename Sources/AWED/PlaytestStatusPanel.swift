import AWEDCore
import SwiftUI

struct PlaytestStatusPanel<Content: View>: View {
    let title: String
    let tileset: Tileset
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.displayScale) private var displayScale

    init(
        _ title: String,
        tileset: Tileset,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.tileset = tileset
        self.content = content()
    }

    var body: some View {
        let theme = PlaytestStatusTheme(tileset: tileset)
        let pixel = 1 / max(displayScale, 1)
        let shape = PlaytestPanelShape(cornerRadius: theme.cornerRadius)
        let shadow = theme.shadow

        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.contentPadding)
            .font(theme.bodyFont)
            .foregroundStyle(theme.primaryText)
            .background {
                theme.surface
                    .opacity(reduceTransparency ? 1 : theme.surfaceOpacity)
                    .clipShape(shape)
            }
            .clipShape(shape)
            .overlay {
                if theme.outerBorderPixels > 0 {
                    shape.strokeBorder(
                        theme.outerBorder,
                        style: StrokeStyle(lineWidth: theme.outerBorderPixels * pixel),
                        antialiased: false
                    )
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                if theme.innerBorderPixels > 0 {
                    shape
                        .inset(by: theme.innerBorderInsetPixels * pixel)
                        .strokeBorder(
                            theme.innerBorder,
                            style: StrokeStyle(lineWidth: theme.innerBorderPixels * pixel),
                            antialiased: false
                        )
                        .allowsHitTesting(false)
                }
            }
            .shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: shadow.xPixels * pixel,
                y: shadow.yPixels * pixel
            )
            .environment(\.colorScheme, theme.preferredColorScheme)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
    }
}

private struct PlaytestPanelShape: InsettableShape {
    let cornerRadius: CGFloat
    private var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, cornerRadius - insetAmount)
        var path = Path()
        path.addRoundedRect(
            in: insetRect,
            cornerSize: CGSize(width: radius, height: radius),
            style: .circular
        )
        return path
    }

    func inset(by amount: CGFloat) -> PlaytestPanelShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
