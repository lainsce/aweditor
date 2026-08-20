import SwiftUI

struct GLWNAquaToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let accentColor = Color("AccentColor")
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    func makeBody(configuration: Configuration) -> some View {
        Button {
            if reduceMotion { configuration.isOn.toggle() }
            else { withAnimation(.easeOut(duration: 0.12)) { configuration.isOn.toggle() } }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill((configuration.isOn ? accentColor : Color.primary).opacity(reduceTransparency ? (configuration.isOn ? 1 : 0.10) : (configuration.isOn ? 1 : 0.035)))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(LinearGradient(colors: isDark ? [.black.opacity(0.38), .black.opacity(0.18), .white.opacity(0.12)] : [.black.opacity(0.16), .black.opacity(0.08), .white.opacity(0.24)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .inset(by: 1)
                            .strokeBorder(LinearGradient(colors: isDark ? [.black.opacity(0.20), .clear, .white.opacity(0.06)] : [.black.opacity(0.10), .clear, .white.opacity(0.16)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(reduceTransparency ? 0.08 : (isDark ? 0.18 : 0.08)), radius: 1, y: 0.5)
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.99), .white.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                    .overlay { Circle().strokeBorder(.white.opacity(isDark ? 0.38 : 0.68), lineWidth: 1) }
                    .overlay { Circle().strokeBorder(.black.opacity(isDark ? 0.30 : 0.16), lineWidth: 0.75) }
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(reduceTransparency ? 0.16 : 0.28), radius: 2.4, y: 1.2)
                    .padding(3)
            }
            .frame(width: 44, height: 28)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityRemoveTraits(.isButton)
        .accessibilityAddTraits(.isToggle)
    }
}

