import AppKit

final class TapScribeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        TapScribeApplicationController.shared.start()
        Task { @MainActor in
            await TapScribeApplicationController.shared.applicationDidFinishLaunching()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
