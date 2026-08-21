import SwiftUI

struct GLWNToolbarMenuLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        GLWNToolbarButtonSurface(
            label: HStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .regular))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            },
            isPressed: false,
            diameter: 38,
            labelWidth: 24
        )
        .accessibilityHidden(true)
        .help(title)
    }
}

/// A toolbar menu whose custom Glasswing surface stays outside the native menu
/// button, so AppKit cannot add a second flat background around the label.
struct GLWNToolbarMenuButton<MenuContent: View>: View {
    let title: String
    let systemImage: String
    private let menuContent: () -> MenuContent

    init(
        title: String,
        systemImage: String,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.title = title
        self.systemImage = systemImage
        self.menuContent = menuContent
    }

    var body: some View {
        ZStack {
            GLWNToolbarMenuLabel(title: title, systemImage: systemImage)

            Menu {
                menuContent()
            } label: {
                Color.clear
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(title)
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .frame(width: 38, height: 38)
            .fixedSize()
        }
        .frame(width: 38, height: 38)
        .fixedSize()
    }
}
