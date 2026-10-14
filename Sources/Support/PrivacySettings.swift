import AppKit
import Foundation

enum PrivacySettings {
    /// System Settings → Privacy & Security → System Audio Recording Only (Sonoma).
    static let systemAudioRecording =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!

    static func openSystemAudioRecording() {
        open(systemAudioRecording, fallbackPanel: "Privacy_AudioCapture")
    }

    private static func open(_ url: URL, fallbackPanel: String) {
        if NSWorkspace.shared.open(url) {
            return
        }
        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(fallbackPanel)")
        if let fallback {
            _ = NSWorkspace.shared.open(fallback)
        }
    }
}
