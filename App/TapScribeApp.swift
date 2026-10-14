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
        TapScribeApp.main()
    }

    private static func bootstrapAppRuntime() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
    }
}

struct TapScribeApp: App {
    @StateObject private var whisperModelStore = WhisperModelStore()
    @AppStorage(WhisperModelStore.onboardingCompletedKey) private var whisperOnboardingCompleted = false

    @State private var isRecording = false
    @State private var session = RecordingSession()
    @AppStorage("lastSessionPath") private var lastSessionPath = ""
    @State private var transcriptionPhase: TranscriptionPhase = .idle
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var recordingsRefreshToken = UUID()
    @State private var didRunLaunchCheck = false

    private var lastSessionURL: URL? {
        guard !lastSessionPath.isEmpty else { return nil }
        return URL(fileURLWithPath: lastSessionPath, isDirectory: true)
    }

    private var recentRecordings: [RecordingSessionEntry] {
        _ = recordingsRefreshToken
        return RecordingsIndex.recent(limit: 15)
    }

    private var statusMainLine: String {
        AppStatusText.mainLine(isRecording: isRecording, transcription: transcriptionPhase)
    }

    private var statusTranscriptLine: String {
        AppStatusText.transcriptLine(for: lastSessionURL, transcription: transcriptionPhase)
    }

    private var modelMenuLine: String {
        if whisperModelStore.isReady {
            return "Model Whisper: gotowy"
        }
        if whisperModelStore.isBusy {
            return "Model Whisper: pobieranie…"
        }
        return "Model Whisper: brak"
    }

    var body: some Scene {
        MenuBarExtra("TapScribe", systemImage: isRecording ? "record.circle.fill" : "waveform") {
            menuContent
        }
        .menuBarExtraStyle(.menu)
    }

    @ViewBuilder
    private var menuContent: some View {
        Group {
        Button(isRecording ? "Stop nagrywania" : "Start nagrywania") {
            Task { await toggleRecording() }
        }

        Text("Nagrywa dźwięk z komputera (YouTube, rozmowy). Nie zmienia wyjścia dźwięku w Ustawieniach.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Divider()

        Menu("Lista nagrań") {
            if recentRecordings.isEmpty {
                Text("Brak nagrań w ~/Recordings")
            } else {
                ForEach(recentRecordings) { entry in
                    Button(entry.menuTitle) {
                        lastSessionPath = entry.url.path
                        RecordingsLocation.openInFinder(sessionDirectory: entry.url)
                        refreshRecordingsList()
                    }
                }
            }
        }

        Button("Pokaż w Finderze") {
            RecordingsLocation.openInFinder(sessionDirectory: lastSessionURL)
        }
        Button("Otwórz folder nagrań…") {
            RecordingsLocation.openRecordingsRootInFinder()
        }

        Divider()

        Menu("Ustawienia") {
            Button("Model transkrypcji…") {
                presentOnboarding()
            }
            Button("Pobierz ponownie model…") {
                Task { await prepareRedownloadOnboarding() }
            }
            Divider()
            Button("Dźwięk systemu (TCC)…") {
                PrivacySettings.openSystemAudioRecording()
            }
        }

        Divider()

        Text(statusMainLine)
            .font(.caption)
        Text(statusTranscriptLine)
            .font(.caption2)
            .foregroundStyle(.secondary)
        Text(modelMenuLine)
            .font(.caption2)
            .foregroundStyle(.secondary)

        Button("Zakończ") {
            transcriptionTask?.cancel()
            whisperModelStore.cancelDownload()
            NSApplication.shared.terminate(nil)
        }
        }
        .task {
            guard !didRunLaunchCheck else { return }
            didRunLaunchCheck = true
            await evaluateOnboardingPresentation()
        }
    }

    @MainActor
    private func presentOnboarding() {
        NSApplication.shared.setActivationPolicy(.regular)
        OnboardingWindowPresenter.present(store: whisperModelStore) {
            dismissOnboarding()
        }
    }

    @MainActor
    private func dismissOnboarding() {
        OnboardingWindowPresenter.dismiss()
        NSApplication.shared.setActivationPolicy(.accessory)
        if whisperModelStore.isReady {
            whisperOnboardingCompleted = true
        }
    }

    @MainActor
    private func prepareRedownloadOnboarding() async {
        whisperModelStore.cancelDownload()
        try? WhisperModelReadiness.removeCachedModels()
        await whisperModelStore.refreshReadyState()
        whisperOnboardingCompleted = false
        presentOnboarding()
    }

    @MainActor
    private func evaluateOnboardingPresentation() async {
        await whisperModelStore.refreshReadyState()
        if whisperModelStore.isReady {
            whisperOnboardingCompleted = true
            return
        }
        if whisperOnboardingCompleted {
            // Model missing despite prior completion — prompt again.
            presentOnboarding()
            return
        }
        presentOnboarding()
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
                refreshRecordingsList()
                transcriptionPhase = .idle
                startTranscription(for: dir)
            } catch {
                isRecording = false
                transcriptionPhase = .failed(message: recordingErrorMessage(for: error))
            }
            return
        }

        transcriptionTask?.cancel()
        transcriptionPhase = .idle
        NSApplication.shared.activate(ignoringOtherApps: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = formatter.string(from: Date())
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recordings/\(name)", isDirectory: true)

        do {
            try session.start(in: dir)
            isRecording = true
            lastSessionPath = dir.path
            transcriptionPhase = .idle
        } catch {
            transcriptionPhase = .failed(message: recordingErrorMessage(for: error))
        }
    }

    @MainActor
    private func startTranscription(for directory: URL?) {
        guard let directory else { return }

        transcriptionTask = Task {
            await whisperModelStore.refreshReadyState()
            guard whisperModelStore.isReady else {
                transcriptionPhase = .failed(message: "brak modelu — Ustawienia → Model transkrypcji…")
                presentOnboarding()
                return
            }

            transcriptionPhase = .running(detail: "przygotowanie…")

            do {
                try await TranscriptionService.transcribeSession(at: directory) { message in
                    Task { @MainActor in
                        let detail = AppStatusText.polishTranscriptionDetail(from: message)
                        transcriptionPhase = .running(detail: detail)
                    }
                }
                transcriptionPhase = .succeeded
                refreshRecordingsList()
            } catch is CancellationError {
                transcriptionPhase = .cancelled
            } catch {
                transcriptionPhase = .failed(message: transcriptionErrorMessage(for: error))
            }
        }
    }

    @MainActor
    private func refreshRecordingsList() {
        recordingsRefreshToken = UUID()
    }

    private func recordingErrorMessage(for error: Error) -> String {
        if let sessionError = error as? RecordingSessionError {
            return sessionError.localizedDescription ?? "błąd nagrywania"
        }
        return error.localizedDescription
    }

    private func transcriptionErrorMessage(for error: Error) -> String {
        if let t = error as? TranscriberError {
            return t.localizedDescription ?? "błąd transkrypcji"
        }
        return error.localizedDescription
    }
}
