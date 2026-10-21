import AppKit
import SwiftUI

@MainActor
final class TranscriptionDialogWindowController: NSWindowController {
    private static var openWindows: [String: TranscriptionDialogWindowController] = [:]

    private let sessionURL: URL
    private let model: TranscriptionDialogModel

    private init(sessionURL: URL) {
        self.sessionURL = sessionURL
        self.model = TranscriptionDialogModel(sessionURL: sessionURL)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Transcription - \(Self.formatDate())"
        window.center()

        let hostingView = NSHostingController(rootView: TranscriptionDialog(model: model))
        window.contentViewController = hostingView

        super.init(window: window)

        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func showOrFocus(for sessionURL: URL) {
        let key = sessionURL.path

        if let existing = openWindows[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let controller = TranscriptionDialogWindowController(sessionURL: sessionURL)
        controller.window?.makeKeyAndOrderFront(nil)

        openWindows[key] = controller
    }

    private static func formatDate() -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: Date())
    }
}

extension TranscriptionDialogWindowController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            let key = self.sessionURL.path
            TranscriptionDialogWindowController.openWindows.removeValue(forKey: key)

            let anyWindowsOpen = !TranscriptionDialogWindowController.openWindows.isEmpty
            if !anyWindowsOpen {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
    }
}
