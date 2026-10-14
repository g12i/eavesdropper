import AppKit
import SwiftUI

@MainActor
enum OnboardingWindowPresenter {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static func present(store: WhisperModelStore, onFinished: @escaping () -> Void) {
        if window == nil {
            let rootView = OnboardingView(modelStore: store) {
                onFinished()
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

            // The title-bar close button must restore accessory mode just like "Później".
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: panel,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { onFinished() }
            }
        }

        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    static func dismiss() {
        guard let window, window.isVisible else { return }
        window.orderOut(nil)
    }
}
