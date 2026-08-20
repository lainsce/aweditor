import SwiftUI

struct GLWNToolbarMenuLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        GLWNToolbarButtonSurface(
            label: Image(systemName: systemImage),
            isPressed: false,
            diameter: 38
        )
        .accessibilityHidden(true)
        .help(title)
    }
}

