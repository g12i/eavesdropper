import AppKit
import Foundation

enum PrivacySettings {
    /// System Settings → Privacy & Security → System Audio Recording Only (Sonoma).
    static let systemAudioRecording =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!

    /// System Settings → Privacy & Security → Microphone (Sonoma).
    static let microphone =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!

    static func openSystemAudioRecording() {
        open(systemAudioRecording, fallbackPanel: "Privacy_AudioCapture")
    }

    static func openMicrophone() {
        open(microphone, fallbackPanel: "Privacy_Microphone")
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
