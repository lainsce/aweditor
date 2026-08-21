import SwiftUI

struct GLWNToolbarSurfaceModifier: ViewModifier {
    let isHovered: Bool
    let isPressed: Bool
    let isFocused: Bool
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var palette: GLWNToolbarMaterialPalette {
        GLWNToolbarMaterialPalette(colorScheme: colorScheme)
    }

    private var glassTopOpacity: Double {
        if palette.isDark {
            return isPressed ? (isHovered ? 0.12 : 0.10) : (isHovered ? 0.28 : 0.22)
        }
        return isPressed ? (isHovered ? 0.10 : 0.08) : (isHovered ? 0.24 : 0.18)
    }

    private var glassBottomOpacity: Double {
        if palette.isDark {
            return isPressed ? 0.12 : (isHovered ? 0.10 : 0.08)
        }
        return isPressed ? 0.08 : (isHovered ? 0.035 : 0.025)
    }

    private var hoverSheenOpacity: Double {
        if palette.isDark {
            return isHovered ? (isPressed ? 0.08 : 0.12) : 0
        }
        return isHovered ? (isPressed ? 0.08 : 0.14) : 0
    }

    private var pressOverlayOpacity: Double {
        if palette.isDark {
            return isPressed ? (isHovered ? 0.10 : 0.12) : 0
        }
        return isPressed ? (isHovered ? 0.07 : 0.08) : 0
    }

    private var highlightTopOpacity: Double {
        if palette.isDark {
            return isPressed ? (isHovered ? 0.50 : 0.44) : (isHovered ? 0.68 : 0.56)
        }
        return isPressed ? (isHovered ? 0.78 : 0.74) : (isHovered ? 1 : 0.95)
    }

    private var highlightBottomOpacity: Double {
        if palette.isDark {
            return isPressed ? (isHovered ? 0.30 : 0.24) : (isHovered ? 0.40 : 0.30)
        }
        return isPressed ? (isHovered ? 0.46 : 0.42) : (isHovered ? 0.72 : 0.65)
    }

    private var outerBorderOpacity: Double {
        if palette.isDark {
            if isPressed {
                return isHovered ? 0.54 : 0.46
            }
            return isHovered ? 0.68 : 0.50
        }
        if isPressed { return isHovered ? 0.78 : 0.72 }
        return isHovered ? 0.95 : 0.85
    }

    private var topRimOpacity: Double {
        if palette.isDark {
            if isPressed {
                return isHovered ? 0.58 : 0.48
            }
            return isHovered ? 0.74 : 0.56
        }
        if isPressed { return isHovered ? 0.78 : 0.68 }
        return isHovered ? 1 : 0.95
    }

    private var lowerDefinitionOpacity: Double {
        if palette.isDark {
            return isPressed ? (isHovered ? 0.28 : 0.24) : (isHovered ? 0.26 : 0.20)
        }
        return isPressed ? (isHovered ? 0.11 : 0.14) : 0.05
    }

    private var contactShadowOpacity: Double {
        if palette.isDark {
            return isPressed ? (isHovered ? 0.20 : 0.22) : (isHovered ? 0.24 : 0.20)
        }
        return isPressed ? (isHovered ? 0.09 : 0.10) : (isHovered ? 0.09 : 0.08)
    }

    private var floatingShadowOpacity: Double {
        if palette.isDark {
            return isPressed ? (isHovered ? 0.16 : 0.18) : (isHovered ? 0.30 : 0.24)
        }
        return isPressed ? (isHovered ? 0.06 : 0.05) : (isHovered ? 0.18 : 0.14)
    }

    private var contactShadowRadius: CGFloat {
        isPressed ? 1 : 2
    }

    private var contactShadowY: CGFloat {
        isPressed ? 0.5 : 1
    }

    private var floatingShadowRadius: CGFloat {
        isPressed ? 1.5 : (isHovered ? 5 : 3.5)
    }

    private var floatingShadowY: CGFloat {
        isPressed ? 1 : 4
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(palette.neutralFallback.opacity(reduceTransparency ? 1 : 0))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(glassTopOpacity),
                                        .clear,
                                        .black.opacity(glassBottomOpacity),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .overlay {
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            .white.opacity(highlightTopOpacity),
                                            .white.opacity(highlightBottomOpacity),
                                            .clear,
                                        ],
                                        center: .bottom,
                                        startRadius: 0,
                                        endRadius: max(38, proxy.size.width * 0.5)
                                    )
                                )
                                .scaleEffect(x: 1, y: 0.72, anchor: .bottom)
                                .opacity(reduceTransparency ? 0 : 1)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(hoverSheenOpacity),
                                        .clear,
                                        palette.definitionColor.opacity(pressOverlayOpacity),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(outerBorderOpacity), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(topRimOpacity), lineWidth: 1)
                    .mask {
                        LinearGradient(
                            colors: [.white, .white.opacity(0.35), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .inset(by: 1)
                    .strokeBorder(palette.definitionColor.opacity(lowerDefinitionOpacity), lineWidth: 1)
                    .mask {
                        LinearGradient(
                            colors: [.clear, .clear, .white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .inset(by: 1)
                    .strokeBorder(Color("AccentColor").opacity(isFocused ? 0.42 : 0), lineWidth: 1)
            }
            .shadow(
                color: palette.shadowColor.opacity(contactShadowOpacity),
                radius: contactShadowRadius,
                x: 0,
                y: contactShadowY
            )
            .shadow(
                color: palette.shadowColor.opacity(floatingShadowOpacity),
                radius: floatingShadowRadius,
                x: 0,
                y: floatingShadowY
            )
    }
}
