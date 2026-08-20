import SwiftUI

struct GLWNSegmentedPicker<Selection: Hashable, ItemLabel: View>: View {
    @Binding private var selection: Selection
    private let options: [Selection]
    private let label: (Selection) -> ItemLabel
    private let accentColor = Color("AccentColor")

    init(selection: Binding<Selection>, options: [Selection], label: @escaping (Selection) -> ItemLabel) {
        self._selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        HStack(spacing: -1) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option == selection
                let isFirst = index == options.startIndex
                let isLast = index == options.count - 1

                Button { selection = option } label: {
                    label(option).frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(
                    GLWNInContentButtonStyle(
                        tone: isSelected ? .accent : .neutral,
                        accentColor: accentColor,
                        cornerRadii: RectangleCornerRadii(
                            topLeading: isFirst ? 7 : 0,
                            bottomLeading: isFirst ? 7 : 0,
                            bottomTrailing: isLast ? 7 : 0,
                            topTrailing: isLast ? 7 : 0
                        ),
                        horizontalPadding: 8,
                        minHeight: 36
                    )
                )
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}

