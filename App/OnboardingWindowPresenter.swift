import AppKit
import SwiftUI

@MainActor
enum OnboardingWindowPresenter {
    private static var window: NSWindow?

    static func present(store: WhisperModelStore, onFinished: @escaping () -> Void) {
        if window == nil {
            let rootView = OnboardingView(modelStore: store) {
                onFinished()
                window?.orderOut(nil)
            }
            let hosting = NSHostingView(rootView: rootView)
            hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 320)

            let panel = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.title = "TapScribe — konfiguracja"
            panel.contentView = hosting
            panel.isReleasedWhenClosed = false
            panel.center()
            window = panel
        }

        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    static func dismiss() {
        window?.orderOut(nil)
    }
}
