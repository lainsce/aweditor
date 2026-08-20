import SwiftUI

/// Groups toolbar controls inside one shared glass surface.
///
/// The controls inside this view intentionally use a plain button style so the
/// material, rim, and shadow belong to the group rather than being repeated on
/// every button.
struct GLWNToolbarControlGroup<Content: View>: View {
    private let content: Content

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var palette: GLWNToolbarMaterialPalette {
        GLWNToolbarMaterialPalette(colorScheme: colorScheme)
    }

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .frame(minHeight: 38, maxHeight: 38)
        .font(.system(size: 20, weight: .regular))
        .foregroundStyle(palette.iconColor)
        .buttonStyle(.plain)
        .modifier(
            GLWNToolbarSurfaceModifier(
                isHovered: isHovered,
                isPressed: false,
                isFocused: false,
                cornerRadius: 999
            )
        )
#if os(macOS) || os(iOS)
        .onHover { isHovered = $0 }
#endif
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isHovered
        )
    }
}
