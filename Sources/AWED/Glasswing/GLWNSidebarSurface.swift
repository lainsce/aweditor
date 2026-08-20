import SwiftUI

#if os(macOS)
import AppKit
#endif

struct GLWNSidebarSurface: View {
    var body: some View {
#if os(macOS)
        ZStack {
            GLWNSidebarMaterialBackground()
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.11)
        }
#else
        Color.clear
            .background(.thinMaterial)
#endif
    }
}

