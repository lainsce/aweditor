import SwiftUI

struct GLWNInsetFieldChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    func body(content: Content) -> some View {
        content
            .contentShape(.rect(cornerRadius: 6))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(reduceTransparency ? 0.10 : (isDark ? 0.06 : 0.025)))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(isDark ? 0.20 : 0.10), .clear, .black.opacity(isDark ? 0.10 : 0.035)], startPoint: .top, endPoint: .bottom))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(LinearGradient(colors: isDark ? [.white.opacity(0.48), .white.opacity(0.16), .black.opacity(0.20)] : [.black.opacity(0.12), .black.opacity(0.03), .white.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .inset(by: 1)
                    .strokeBorder(LinearGradient(colors: isDark ? [.clear, .clear, .black.opacity(0.16)] : [.black.opacity(0.08), .clear, .white.opacity(0.18)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isDark ? 0.18 : 0.035), radius: 2, x: 0, y: 1)
    }
}

