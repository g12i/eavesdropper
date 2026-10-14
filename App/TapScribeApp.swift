import AppKit
import SwiftUI

@main
enum TapScribeMain {
    static func main() {
        if CommandLine.arguments.contains("--probe-capture") {
            bootstrapAppRuntime()
            CaptureDiagnostics.printReport()
            exit(0)
        }

        if CommandLine.arguments.contains("--headless") || CommandLine.arguments.contains("--transcribe") {
            bootstrapAppRuntime()
            let group = DispatchGroup()
            group.enter()
            Task {
                _ = await HeadlessRunner.runIfNeeded()
                group.leave()
            }
            group.wait()
            exit(2)
        }

        runMenuBarApplication()
    }

    private static func bootstrapAppRuntime() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
    }

    private static func runMenuBarApplication() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = TapScribeAppDelegate()
        app.run()
    }
}
