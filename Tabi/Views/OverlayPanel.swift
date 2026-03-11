import AppKit
import SwiftUI

// MARK: - OverlayPanel

final class OverlayPanel: NSPanel {

    init(viewModel: TabiViewModel) {
        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            return
        }

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // NSVisualEffectView for blur background
        let blurView = NSVisualEffectView(frame: screen.frame)
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]

        let hostingView = NSHostingView(rootView: SwitcherOverlay(viewModel: viewModel))
        hostingView.frame = screen.frame
        hostingView.autoresizingMask = [.width, .height]

        blurView.addSubview(hostingView)
        contentView = blurView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
