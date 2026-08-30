import CoreText
import Foundation

/// Registers the small, open-font set used by the era-specific playtest
/// status panels. Registration is process-local and idempotent; if a font is
/// unavailable, SwiftUI falls back to its system font without affecting the
/// panel's layout or accessibility.
enum PlaytestFontCatalog {
    private static let resources = [
        "PressStart2P-Regular",
        "VT323-Regular",
        "Silkscreen-Regular",
        "Silkscreen-Bold",
        "ShareTechMono-Regular",
        "Rajdhani-Regular",
        "Rajdhani-SemiBold"
    ]

    @MainActor
    static func registerBundledFonts() {
        guard let resourceDirectory = Bundle.main.resourceURL?.appending(path: "Fonts") else { return }

        for resource in resources {
            let url = resourceDirectory.appendingPathComponent("\(resource).ttf")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
