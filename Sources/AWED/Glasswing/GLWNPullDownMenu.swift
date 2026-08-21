import SwiftUI

struct GLWNPullDownMenu<Selection: Hashable, ItemLabel: View>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Selection
    private let options: [Selection]
    private let showsTitle: Bool
    private let label: (Selection) -> ItemLabel
    private let accentColor = Color("AccentColor")

    init(_ title: LocalizedStringKey, selection: Binding<Selection>, options: [Selection], showsTitle: Bool = true, label: @escaping (Selection) -> ItemLabel) {
        self.title = title
        self._selection = selection
        self.options = options
        self.showsTitle = showsTitle
        self.label = label
    }

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button { selection = option } label: { label(option) }
                    .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        } label: {
            HStack(spacing: 8) {
                if showsTitle {
                    Text(title).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                }
                label(selection).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 36, alignment: .leading)
        }
        .menuStyle(.button)
        .buttonStyle(GLWNInContentButtonStyle(tone: .neutral, accentColor: accentColor, horizontalPadding: 10, minHeight: 36))
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(title)
    }
}
