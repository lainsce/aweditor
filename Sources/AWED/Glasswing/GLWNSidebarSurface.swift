import SwiftUI

#if os(macOS)
import AppKit
#endif

struct GLWNSidebarSurface: View {
    private let blendingMode: NSVisualEffectView.BlendingMode

    init(blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.blendingMode = blendingMode
    }

    var body: some View {
#if os(macOS)
        ZStack {
            GLWNSidebarMaterialBackground(blendingMode: blendingMode)
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.11)
        }
        .ignoresSafeArea(.container, edges: .top)
#else
        Color.clear
            .background(.thinMaterial)
#endif
    }
}
