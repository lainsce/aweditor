import SwiftUI

struct GLWNSegmentedPicker<Selection: Hashable, ItemLabel: View>: View {
    @Binding private var selection: Selection
    private let options: [Selection]
    private let label: (Selection) -> ItemLabel
    private let accentColor = Color("AccentColor")

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredIndex: Int?

    init(selection: Binding<Selection>, options: [Selection], label: @escaping (Selection) -> ItemLabel) {
        self._selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option == selection

                Button { selection = option } label: {
                    label(option)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            isSelected
                                ? accentColor.opacity(colorScheme == .dark ? 0.44 : 0.24)
                                : (hoveredIndex == index ? Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10) : .clear)
                        )
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(accentColor.opacity(reduceTransparency ? 1 : 0.70), lineWidth: 1)
                    }
                }
                .onHover { isHovered in
                    hoveredIndex = isHovered ? index : (hoveredIndex == index ? nil : hoveredIndex)
                }
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
        .modifier(
            GLWNToolbarSurfaceModifier(
                isHovered: hoveredIndex != nil,
                isPressed: false,
                isFocused: false,
                cornerRadius: 8
            )
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selection)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredIndex)
    }
}
