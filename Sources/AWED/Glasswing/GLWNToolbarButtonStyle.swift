import SwiftUI

struct GLWNToolbarButtonStyle: ButtonStyle {
    private let diameter: CGFloat = 38

    func makeBody(configuration: Configuration) -> some View {
        GLWNToolbarButtonSurface(
            label: configuration.label,
            isPressed: configuration.isPressed,
            diameter: diameter
        )
    }
}

