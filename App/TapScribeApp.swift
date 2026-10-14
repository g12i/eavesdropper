import AppKit
import SwiftUI

@main
enum TapScribeMain {
    static func main() {
        if CommandLine.arguments.contains("--probe-capture") {
            bootstrapAppRuntime()
            let includeMic = !CommandLine.arguments.contains("--no-mic")
            CaptureDiagnostics.printReport(includeMicrophone: includeMic)
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
        TapScribeApp.main()
    }

    private static func bootstrapAppRuntime() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
    }
}

struct TapScribeApp: App {
    @State private var isRecording = false
    @State private var session = RecordingSession()
    @State private var recordMicrophone = true
    @State private var status = "Gotowy"

    private var bundleLabel: String {
        Bundle.main.bundleIdentifier ?? "?"
    }

    var body: some Scene {
        MenuBarExtra("TapScribe", systemImage: isRecording ? "record.circle.fill" : "waveform") {
            Button(isRecording ? "Stop nagrywania" : "Start nagrywania") {
                Task { await toggleRecording() }
            }
            Toggle("Nagrywaj mikrofon", isOn: $recordMicrophone)
                .disabled(isRecording)
            Divider()
            Button("Ustawienia: dźwięk systemu…") {
                PrivacySettings.openSystemAudioRecording()
            }
            Button("Ustawienia: mikrofon…") {
                PrivacySettings.openMicrophone()
            }
            Divider()
            Text(status)
                .font(.caption)
            Text("Bundle: \(bundleLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Zakończ") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }

    @MainActor
    private func toggleRecording() async {
        if isRecording {
            do {
                try session.stop()
                status = "Transkrybuję…"
                if let dir = session.outputDirectory {
                    try await HeadlessRunner.transcribeSession(at: dir)
                    status = "Transkrypt gotowy"
                } else {
                    status = "Gotowy"
                }
            } catch {
                status = userFacingStatus(for: error)
            }
            isRecording = false
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = formatter.string(from: Date())
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recordings/\(name)", isDirectory: true)

        do {
            try session.start(in: dir, recordMicrophone: recordMicrophone)
            isRecording = true
            status = "Nagrywanie…"
        } catch {
            status = userFacingStatus(for: error)
        }
    }

    private func userFacingStatus(for error: Error) -> String {
        if let mic = error as? MicRecorderError, mic == .microphonePermissionDenied {
            return "Brak zgody na mikrofon — otwórz Ustawienia poniżej."
        }
        if let sys = error as? SystemAudioCaptureError {
            switch sys {
            case .denied:
                return "Brak zgody na dźwięk systemu — otwórz Ustawienia poniżej."
            case .tapFailed(let code):
                return "Tap dźwięku systemu nie wystartował (kod \(code))."
            }
        }
        return "Błąd: \(error.localizedDescription)"
    }
}
