import SwiftUI

struct GLWNToolbarMaterialPalette {
    let colorScheme: ColorScheme

    var isDark: Bool {
        colorScheme == .dark
    }

    var iconColor: Color {
        isDark
            ? Color(red: 229 / 255, green: 231 / 255, blue: 231 / 255)
            : Color(red: 98 / 255, green: 101 / 255, blue: 101 / 255)
    }

    var shadowColor: Color {
        isDark
            ? .black
            : Color(red: 70 / 255, green: 78 / 255, blue: 82 / 255)
    }

    var definitionColor: Color {
        isDark
            ? .black
            : Color(red: 80 / 255, green: 90 / 255, blue: 95 / 255)
    }

    var neutralFallback: Color {
        isDark ? .black.opacity(0.24) : Color.primary.opacity(0.10)
    }
}

