import AppKit

final class EavesdropperAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as host; skip the status item, onboarding window and timers.
        guard NSClassFromString("XCTestCase") == nil else { return }
        MainActor.assumeIsolated {
            EavesdropperApplicationController.shared.applicationDidFinishLaunching()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
