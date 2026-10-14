import AppKit
import Foundation
import SwiftUI

extension Notification.Name {
    static let tapScribeMenuRebuild = Notification.Name("TapScribeMenuRebuild")
}

@MainActor
final class TapScribeApplicationController: ObservableObject {
    static let shared = TapScribeApplicationController()

    let whisperModelStore = WhisperModelStore()

    @Published private(set) var isRecording = false
    private(set) var session = RecordingSession()
    @Published var lastSessionPath: String {
        didSet { UserDefaults.standard.set(lastSessionPath, forKey: Self.lastSessionPathKey) }
    }
    @Published var transcriptionPhase: TranscriptionPhase = .idle

    private var transcriptionTask: Task<Void, Never>?
    private var recordingsRefreshToken = UUID()
    private var didRunLaunchCheck = false

    private static let lastSessionPathKey = "lastSessionPath"
    private static let onboardingKey = WhisperModelStore.onboardingCompletedKey

    private init() {
        lastSessionPath = UserDefaults.standard.string(forKey: Self.lastSessionPathKey) ?? ""
    }

    var lastSessionURL: URL? {
        guard !lastSessionPath.isEmpty else { return nil }
        return URL(fileURLWithPath: lastSessionPath, isDirectory: true)
    }

    var recordingMenuRows: [RecordingMenuRow] {
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

    var globalStatusLabel: String {
        GlobalStatusPresentation.label(
            isRecording: isRecording,
            transcription: transcriptionPhase,
            modelReady: whisperModelStore.isReady,
            modelBusy: whisperModelStore.isBusy
        )
    }

    var globalStatusTone: RecordingStatusTone {
        GlobalStatusPresentation.tone(
            isRecording: isRecording,
            transcription: transcriptionPhase,
            modelReady: whisperModelStore.isReady,
            modelBusy: whisperModelStore.isBusy
        )
    }

    func start() {
        NotificationCenter.default.addObserver(
            forName: .tapScribeMenuRebuild,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                TapScribeStatusMenuController.shared.refreshIfNeeded()
            }
        }

        startPeriodicRefreshWhenBusy()
    }

    func applicationDidFinishLaunching() async {
        await whisperModelStore.refreshReadyState()
        refreshRecordingsList()
        TapScribeStatusMenuController.shared.install()
        TapScribeStatusMenuController.shared.rebuildMenu()

        guard !didRunLaunchCheck else { return }
        didRunLaunchCheck = true
        await evaluateOnboardingPresentation()
    }

    func notifyMenuRebuild() {
        TapScribeStatusMenuController.shared.rebuildMenu()
        TapScribeStatusMenuController.shared.updateStatusIcon(isRecording: isRecording)
        NotificationCenter.default.post(name: .tapScribeMenuRebuild, object: nil)
    }

    private func startPeriodicRefreshWhenBusy() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let busy = self.isRecording
                    || self.whisperModelStore.isBusy
                    || self.transcriptionPhase.isActive
                if busy {
                    self.notifyMenuRebuild()
                }
            }
        }
    }

    func presentOnboarding() {
        NSApplication.shared.setActivationPolicy(.regular)
        OnboardingWindowPresenter.present(store: whisperModelStore) {
            self.dismissOnboarding()
        }
    }

    func dismissOnboarding() {
        OnboardingWindowPresenter.dismiss()
        NSApplication.shared.setActivationPolicy(.accessory)
        if whisperModelStore.isReady {
            UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        }
        notifyMenuRebuild()
    }

    func prepareRedownloadOnboarding() async {
        whisperModelStore.cancelDownload()
        try? WhisperModelReadiness.removeCachedModels()
        await whisperModelStore.refreshReadyState()
        UserDefaults.standard.set(false, forKey: Self.onboardingKey)
        presentOnboarding()
    }

    private func evaluateOnboardingPresentation() async {
        await whisperModelStore.refreshReadyState()
        if whisperModelStore.isReady {
            UserDefaults.standard.set(true, forKey: Self.onboardingKey)
            return
        }
        presentOnboarding()
    }

    func toggleRecording() async {
        if isRecording {
            let dir = session.outputDirectory
            do {
                try session.stop()
                isRecording = false
                if let dir {
                    lastSessionPath = dir.path
                    refreshRecordingsList()
                    if SessionRecordingDuration.isTooShortForTranscription(in: dir) {
                        transcriptionPhase = .skippedTooShort
                        notifyMenuRebuild()
                        return
                    }
                }
                transcriptionPhase = .idle
                notifyMenuRebuild()
                startTranscription(for: dir)
            } catch {
                isRecording = false
                transcriptionPhase = .failed(message: recordingErrorMessage(for: error))
                notifyMenuRebuild()
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
            notifyMenuRebuild()
        } catch {
            transcriptionPhase = .failed(message: recordingErrorMessage(for: error))
            notifyMenuRebuild()
        }
    }

    func openRecording(_ row: RecordingMenuRow) {
        lastSessionPath = row.url.path
        RecordingsLocation.revealSessionFolder(row.url)
        refreshRecordingsList()
        notifyMenuRebuild()
    }

    func quit() {
        transcriptionTask?.cancel()
        whisperModelStore.cancelDownload()
        NSApplication.shared.terminate(nil)
    }

    private func startTranscription(for directory: URL?) {
        guard let directory else { return }

        if SessionRecordingDuration.isTooShortForTranscription(in: directory) {
            transcriptionPhase = .skippedTooShort
            refreshRecordingsList()
            notifyMenuRebuild()
            return
        }

        transcriptionTask = Task {
            await whisperModelStore.refreshReadyState()
            guard whisperModelStore.isReady else {
                transcriptionPhase = .failed(message: "brak modelu — Ustawienia → Model transkrypcji…")
                refreshRecordingsList()
                notifyMenuRebuild()
                presentOnboarding()
                return
            }

            transcriptionPhase = .running(detail: "przygotowanie…")
            refreshRecordingsList()
            notifyMenuRebuild()

            do {
                try await TranscriptionService.transcribeSession(at: directory) { message in
                    Task { @MainActor in
                        let detail = AppStatusText.polishTranscriptionDetail(from: message)
                        self.transcriptionPhase = .running(detail: detail)
                        self.notifyMenuRebuild()
                    }
                }
                transcriptionPhase = .succeeded
                refreshRecordingsList()
                notifyMenuRebuild()
            } catch is CancellationError {
                transcriptionPhase = .cancelled
                refreshRecordingsList()
                notifyMenuRebuild()
            } catch {
                transcriptionPhase = .failed(message: transcriptionErrorMessage(for: error))
                refreshRecordingsList()
                notifyMenuRebuild()
            }
        }
    }

    func refreshRecordingsList() {
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

private extension TranscriptionPhase {
    var isActive: Bool {
        if case .running = self { return true }
        return false
    }
}
