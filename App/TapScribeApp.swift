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
    @AppStorage("recordMicrophone") private var recordMicrophone = false
    @AppStorage("lastSessionPath") private var lastSessionPath = ""
    @State private var status = "Gotowy"
    @State private var transcriptionTask: Task<Void, Never>?

    private var lastSessionURL: URL? {
        guard !lastSessionPath.isEmpty else { return nil }
        return URL(fileURLWithPath: lastSessionPath, isDirectory: true)
    }

    private var recordingsPathHint: String {
        if let lastSessionURL {
            return "Ostatnie: \(RecordingsLocation.displayPath(for: lastSessionURL))"
        }
        return "Nagrania: ~/Recordings/<YYYY-MM-DD_HH-mm-ss>/"
    }

    private var bundleLabel: String {
        Bundle.main.bundleIdentifier ?? "?"
    }

    var body: some Scene {
        MenuBarExtra("TapScribe", systemImage: isRecording ? "record.circle.fill" : "waveform") {
            Button(isRecording ? "Stop nagrywania" : "Start nagrywania") {
                Task { await toggleRecording() }
            }
            Text("Nagrywa dźwięk z komputera (YouTube, rozmowy w aplikacjach). Nie pojawia się na liście wyjść w Ustawieniach → Dźwięk.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Nagrywaj mikrofon (Twój głos)", isOn: $recordMicrophone)
                .disabled(isRecording)
            Divider()
            Button("Pokaż w Finderze") {
                RecordingsLocation.openInFinder(sessionDirectory: lastSessionURL)
            }
            Button("Otwórz folder nagrań…") {
                RecordingsLocation.openRecordingsRootInFinder()
            }
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
            Text(recordingsPathHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Bundle: \(bundleLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Zakończ") {
                transcriptionTask?.cancel()
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }

    @MainActor
    private func toggleRecording() async {
        if isRecording {
            let dir = session.outputDirectory
            do {
                try session.stop()
                isRecording = false
                if let dir {
                    lastSessionPath = dir.path
                }
                status = "Nagranie zapisane (dźwięk systemu\(recordMicrophone ? " + mikrofon" : ""))."
                startTranscription(for: dir)
            } catch {
                isRecording = false
                status = recordingErrorMessage(for: error)
            }
            return
        }

        transcriptionTask?.cancel()
        NSApplication.shared.activate(ignoringOtherApps: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = formatter.string(from: Date())
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recordings/\(name)", isDirectory: true)

        do {
            try session.start(in: dir, recordMicrophone: recordMicrophone)
            isRecording = true
            status = recordMicrophone
                ? "Nagrywanie: dźwięk systemu + mikrofon…"
                : "Nagrywanie: dźwięk systemu…"
        } catch {
            status = recordingErrorMessage(for: error)
        }
    }

    @MainActor
    private func startTranscription(for directory: URL?) {
        guard let directory else { return }
        transcriptionTask = Task {
            do {
                try await TranscriptionService.transcribeSession(at: directory) { message in
                    Task { @MainActor in
                        status = message
                    }
                }
                status = "Transkrypt gotowy"
            } catch is CancellationError {
                status = "Transkrypcja anulowana (nagranie zapisane)."
            } catch {
                status = "Nagranie OK. \(transcriptionErrorMessage(for: error))"
            }
        }
    }

    private func recordingErrorMessage(for error: Error) -> String {
        if let sessionError = error as? RecordingSessionError {
            switch sessionError {
            case .systemAudio:
                return "Nagrywanie — dźwięk systemu: \(sessionError.localizedDescription ?? "błąd")"
            case .microphone:
                return "Nagrywanie — mikrofon: \(sessionError.localizedDescription ?? "błąd") (dźwięk systemu działa po wyłączeniu mikrofonu)"
            }
        }
        return "Nagrywanie: \(error.localizedDescription)"
    }

    private func transcriptionErrorMessage(for error: Error) -> String {
        if let t = error as? TranscriberError {
            return t.localizedDescription ?? "błąd transkrypcji"
        }
        return "Transkrypcja: \(error.localizedDescription)"
    }
}
