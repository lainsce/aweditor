import SwiftUI

/// Glasswing's Aqua-inspired in-content action treatment.
struct GLWNInContentButtonStyle: ButtonStyle {
    enum Tone { case accent, neutral }

    private let tone: Tone
    private let accentColor: Color
    private let cornerRadii: RectangleCornerRadii
    private let horizontalPadding: CGFloat
    private let minHeight: CGFloat
    private let labelColorOverride: Color?

    init(tone: Tone = .accent, accentColor: Color = Color("AccentColor"), cornerRadius: CGFloat = 7, cornerRadii: RectangleCornerRadii? = nil, horizontalPadding: CGFloat = 14, minHeight: CGFloat = 32, labelColor: Color? = nil) {
        self.tone = tone
        self.accentColor = accentColor
        self.cornerRadii = cornerRadii ?? RectangleCornerRadii(topLeading: cornerRadius, bottomLeading: cornerRadius, bottomTrailing: cornerRadius, topTrailing: cornerRadius)
        self.horizontalPadding = horizontalPadding
        self.minHeight = minHeight
        self.labelColorOverride = labelColor
    }

    func makeBody(configuration: Configuration) -> some View {
        Body(label: configuration.label, isPressed: configuration.isPressed, tone: tone, accentColor: accentColor, cornerRadii: cornerRadii, horizontalPadding: horizontalPadding, minHeight: minHeight, labelColorOverride: labelColorOverride)
    }

    private struct Body<Label: View>: View {
        let label: Label
        let isPressed: Bool
        let tone: GLWNInContentButtonStyle.Tone
        let accentColor: Color
        let cornerRadii: RectangleCornerRadii
        let horizontalPadding: CGFloat
        let minHeight: CGFloat
        let labelColorOverride: Color?

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var isDarkMode: Bool { colorScheme == .dark }
        private var isAccentTone: Bool { if case .accent = tone { return true }; return false }
        private var baseColor: Color {
            switch tone {
            case .accent: accentColor
            case .neutral: isDarkMode ? Color(red: 61 / 255, green: 67 / 255, blue: 74 / 255) : Color(red: 236 / 255, green: 238 / 255, blue: 240 / 255)
            }
        }
        private var labelColor: Color {
            if let labelColorOverride { return labelColorOverride }
            switch tone {
            case .accent: return Color.white
            case .neutral: return isDarkMode ? Color(red: 242 / 255, green: 243 / 255, blue: 244 / 255) : Color(red: 47 / 255, green: 49 / 255, blue: 51 / 255)
            }
        }
        private var topSheenOpacity: Double {
            if reduceTransparency { return 0 }
            if isPressed { return isHovered ? 0.08 : 0.05 }
            if !isDarkMode && !isAccentTone { return isHovered ? 0.80 : 0.72 }
            if !isDarkMode && isAccentTone { return isHovered ? 0.46 : 0.38 }
            return isHovered ? 0.20 : 0.14
        }
        private var aquaBottomGlowOpacity: Double {
            guard !reduceTransparency else { return 0 }
            if isDarkMode { return isPressed ? 0.04 : (isHovered ? 0.10 : 0.07) }
            return isPressed ? 0.08 : (isHovered ? 0.38 : 0.30)
        }
        private var aquaCenterBandOpacity: Double {
            guard !reduceTransparency else { return 0 }
            if isPressed { return 0.04 }
            if isDarkMode { return isHovered ? 0.12 : 0.08 }
            if isAccentTone { return isHovered ? 0.14 : 0.11 }
            return isHovered ? 0.06 : 0.04
        }
        private var aquaCenterBandColor: Color { isDarkMode ? .white : .black }
        private var aquaSurfaceGradient: LinearGradient {
            LinearGradient(gradient: Gradient(stops: [
                .init(color: .white.opacity(topSheenOpacity), location: 0.00),
                .init(color: .white.opacity(topSheenOpacity * 0.84), location: 0.08),
                .init(color: .white.opacity(topSheenOpacity * 0.58), location: 0.18),
                .init(color: .white.opacity(topSheenOpacity * 0.28), location: 0.30),
                .init(color: .clear, location: 0.43),
                .init(color: aquaCenterBandColor.opacity(aquaCenterBandOpacity * 0.35), location: 0.50),
                .init(color: aquaCenterBandColor.opacity(aquaCenterBandOpacity), location: 0.57),
                .init(color: aquaCenterBandColor.opacity(aquaCenterBandOpacity * 0.62), location: 0.64),
                .init(color: .white.opacity(aquaBottomGlowOpacity * 0.18), location: 0.72),
                .init(color: .white.opacity(aquaBottomGlowOpacity * 0.40), location: 0.82),
                .init(color: .white.opacity(aquaBottomGlowOpacity * 0.62), location: 0.93),
                .init(color: .white.opacity(aquaBottomGlowOpacity * 0.72), location: 1.00),
            ]), startPoint: .top, endPoint: .bottom)
        }
        private var aquaOuterBorderColor: Color { isDarkMode ? .black : Color(white: 70 / 255) }
        private var aquaOuterBorderOpacity: Double { isDarkMode ? (isPressed ? 0.42 : 0.32) : (isPressed ? 0.54 : 0.44) }
        private var textInsetShadowOpacity: Double { isPressed ? (isAccentTone ? 0.42 : 0.30) : (isAccentTone ? 0.28 : 0.20) }
        private var textInsetHighlightOpacity: Double { isPressed ? (isAccentTone ? 0.16 : 0.26) : (isAccentTone ? 0.20 : 0.38) }
        private var pressedWashOpacity: Double { isPressed ? (isDarkMode ? 0.16 : 0.07) : 0 }
        private var upperRimOpacity: Double {
            if isDarkMode { return isPressed ? (isHovered ? 0.40 : 0.34) : (isHovered ? 0.72 : 0.60) }
            return isPressed ? (isHovered ? 0.38 : 0.32) : (isHovered ? 0.58 : 0.50)
        }
        private var shadowOpacity: Double { isDarkMode ? (isPressed ? 0.08 : (isHovered ? 0.30 : 0.24)) : (isPressed ? 0.08 : (isHovered ? 0.24 : 0.18)) }
        private var buttonShape: UnevenRoundedRectangle { UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous) }

        var body: some View {
            label
                .font(.body.weight(.medium))
                .foregroundStyle(labelColor)
                .shadow(color: .black.opacity(textInsetShadowOpacity), radius: 0.35, x: -0.25, y: -0.75)
                .shadow(color: .white.opacity(textInsetHighlightOpacity), radius: 0.35, x: 0.25, y: 0.75)
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: minHeight)
                .contentShape(buttonShape)
                .background { buttonShape.fill(baseColor).overlay { buttonShape.fill(aquaSurfaceGradient) }.overlay { buttonShape.fill(.black.opacity(pressedWashOpacity)) } }
                .overlay { buttonShape.strokeBorder(aquaOuterBorderColor.opacity(aquaOuterBorderOpacity), lineWidth: 1) }
                .overlay { buttonShape.inset(by: 1).strokeBorder(LinearGradient(colors: [.white.opacity(upperRimOpacity), .white.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
                .shadow(color: .black.opacity(shadowOpacity), radius: isPressed ? 0.5 : (isHovered ? 2.0 : 1.5), x: 0, y: isPressed ? 1.0 : 1.5)
                .opacity(isEnabled ? 1 : 0.46)
                .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.96 : 1))
                .offset(y: reduceMotion ? 0 : (isPressed ? 1.25 : 0))
#if os(macOS) || os(iOS)
                .onHover { isHovered = $0 }
#endif
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: isPressed)
        }
    }
}
