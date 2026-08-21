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

/// A value slider with the same inset material, rim, and hit-target geometry
/// as Glasswing text fields. The native slider remains responsible for its
/// keyboard and pointer semantics while this wrapper owns its visible chrome.
struct GLWNSliderField: View {
    @Binding var value: Double

    let bounds: ClosedRange<Double>
    let step: Double
    let tint: Color
    let onEditingChanged: (Bool) -> Void

    init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double>,
        step: Double,
        tint: Color = Color("AccentColor"),
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.tint = tint
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        Slider(
            value: $value,
            in: bounds,
            step: step,
            onEditingChanged: onEditingChanged
        )
        .tint(tint)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .modifier(GLWNInsetFieldChrome())
    }
}

/// A compact Glasswing progress track for in-content status values.
struct GLWNProgressBar: View {
    let value: Double
    let total: Double
    let tint: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(min(max(value / total, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(reduceTransparency ? 0.12 : 0.05))
                    }
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: proxy.size.width * fraction)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.30), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
            }
            .frame(height: 8)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
