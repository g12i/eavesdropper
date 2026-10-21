import AppKit
import SwiftUI

@main
enum EavesdropperMain {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--probe-capture") || args.contains("--headless") || args.contains("--transcribe") {
            bootstrapAppRuntime()
            Task {
                _ = await HeadlessRunner.runIfNeeded()
                exit(2)
            }
            // Keep the main queue serviced: capture setup hops to the main actor for TCC activation.
            dispatchMain()
        }

        runMenuBarApplication()
    }

    private static func bootstrapAppRuntime() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
    }

    /// `NSApplication.delegate` is weak; this keeps the delegate alive for the app's lifetime.
    private static let appDelegate = EavesdropperAppDelegate()

    private static func runMenuBarApplication() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = appDelegate
        app.run()
    }
}
