import SwiftUI

#if os(macOS)
import AppKit

struct GLWNSidebarMaterialBackground: NSViewRepresentable {
    let blendingMode: NSVisualEffectView.BlendingMode

    init(blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = .sidebar
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        view.isEmphasized = false
    }
}
#endif
