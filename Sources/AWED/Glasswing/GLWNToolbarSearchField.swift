import SwiftUI

/// A compact toolbar search field that mirrors Habito's inset glass treatment.
/// AWED does not currently place a search field in its toolbar, but keeping the
/// control here makes future toolbar search additions use the same accessible
/// surface without changing the editor's layout.
struct GLWNToolbarSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var isFocused

    private let cornerRadius: CGFloat = 999

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFocused)
                .submitLabel(.search)
                .accessibilityLabel(placeholder)

            if !text.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    text = ""
                    isFocused = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 38, minHeight: 38, maxHeight: 38)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 200, idealWidth: 200, maxWidth: 200)
        .frame(height: 38)
        .contentShape(.rect(cornerRadius: cornerRadius))
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(reduceTransparency ? 0.10 : 0.025))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(isFocused ? 0.14 : 0.08),
                                    .clear,
                                    .black.opacity(0.035),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .black.opacity(0.12),
                            .black.opacity(0.03),
                            .white.opacity(isFocused ? 0.38 : 0.28),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .inset(by: 1)
                .strokeBorder(
                    LinearGradient(
                        colors: [.black.opacity(0.10), .clear, .white.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color("AccentColor").opacity(isFocused ? 0.42 : 0), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isFocused ? 0.045 : 0.03), radius: 1, x: 0, y: 0)
        .onTapGesture {
            isFocused = true
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isFocused
        )
    }
}
