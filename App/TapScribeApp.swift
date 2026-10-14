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

    private var recordingMenuRows: [RecordingMenuRow] {
        _ = recordingsRefreshToken
        return RecordingMenuPresentation.rows(
            recent: RecordingsIndex.recent(limit: 15),
            activeRecordingDirectory: session.outputDirectory,
            isRecording: isRecording,
            lastSessionPath: lastSessionPath,
            transcription: transcriptionPhase,
            modelReady: whisperModelStore.isReady
        )
    }

    private var globalStatusLabel: String {
        GlobalStatusPresentation.label(
            isRecording: isRecording,
            transcription: transcriptionPhase,
            modelReady: whisperModelStore.isReady,
            modelBusy: whisperModelStore.isBusy
        )
    }

    private var globalStatusTone: RecordingStatusTone {
        GlobalStatusPresentation.tone(
            isRecording: isRecording,
            transcription: transcriptionPhase,
            modelReady: whisperModelStore.isReady,
            modelBusy: whisperModelStore.isBusy
        )
    }

    var body: some Scene {
        MenuBarExtra("TapScribe", systemImage: isRecording ? "record.circle.fill" : "waveform") {
            TapScribeMenuPanelView(
                globalStatusLabel: globalStatusLabel,
                globalStatusTone: globalStatusTone,
                rows: recordingMenuRows,
                isRecording: isRecording,
                onToggleRecording: { Task { await toggleRecording() } },
                onSelectRow: { row in
                    lastSessionPath = row.url.path
                    RecordingsLocation.openInFinder(sessionDirectory: row.url)
                    refreshRecordingsList()
                },
                onShowInFinder: {
                    RecordingsLocation.openInFinder(sessionDirectory: lastSessionURL)
                },
                onOpenModelSettings: { presentOnboarding() },
                onRedownloadModel: { Task { await prepareRedownloadOnboarding() } },
                onOpenSystemAudioSettings: { PrivacySettings.openSystemAudioRecording() },
                onQuit: {
                    transcriptionTask?.cancel()
                    whisperModelStore.cancelDownload()
                    NSApplication.shared.terminate(nil)
                },
                onAppearRefresh: {
                    Task { @MainActor in
                        await whisperModelStore.refreshReadyState()
                        refreshRecordingsList()
                        guard !didRunLaunchCheck else { return }
                        didRunLaunchCheck = true
                        await evaluateOnboardingPresentation()
                    }
                }
            )
        }
        .menuBarExtraStyle(.window)
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
            refreshRecordingsList()
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
                refreshRecordingsList()
                presentOnboarding()
                return
            }

            transcriptionPhase = .running(detail: "przygotowanie…")
            refreshRecordingsList()

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
                refreshRecordingsList()
            } catch {
                transcriptionPhase = .failed(message: transcriptionErrorMessage(for: error))
                refreshRecordingsList()
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
