import AppKit
import Foundation
import OSLog

@MainActor
final class TapScribeApplicationController: ObservableObject {
    static let shared = TapScribeApplicationController()

    let whisperModelStore = WhisperModelStore()

    @Published private(set) var isRecording = false
    /// True while start/stop is in flight (e.g. the TCC prompt is up); blocks double toggles.
    @Published private(set) var isTogglingRecording = false
    private(set) var recordingStartedAt: Date?
    private(set) var activeRecordingDirectory: URL?
    private let session = RecordingSession()

    /// Per-session transcription phase for this app run, keyed by session folder path.
    @Published private(set) var transcriptionStates: [String: TranscriptionPhase] = [:]
    private var transcriptionQueue: [URL] = []
    private var transcriptionTask: Task<Void, Never>?
    private var tickTimer: Timer?
    private var didRunLaunchCheck = false

    private let logger = Logger(subsystem: "com.tapscribe.app", category: "AppController")
    private static let onboardingKey = WhisperModelStore.onboardingCompletedKey

    private init() {}

    var isTranscribing: Bool {
        transcriptionTask != nil
    }

    var recordingMenuRows: [RecordingMenuRow] {
        RecordingMenuPresentation.rows(
            recent: RecordingsIndex.recent(limit: 15),
            activeRecordingDirectory: activeRecordingDirectory,
            isRecording: isRecording,
            transcriptionStates: transcriptionStates,
            modelReady: whisperModelStore.isReady
        )
    }

    var recordingElapsedMMSS: String? {
        guard isRecording, let recordingStartedAt else { return nil }
        return RecordingElapsedFormat.mmss(since: recordingStartedAt)
    }

    var menuHeader: MenuHeaderModel {
        MenuHeaderPresentation.model(
            isRecording: isRecording,
            recordingElapsedMMSS: recordingElapsedMMSS,
            systemAudioStatus: SystemAudioCapturePermission.currentStatus(),
            modelReady: whisperModelStore.isReady,
            modelBusy: whisperModelStore.isBusy
        )
    }

    func applicationDidFinishLaunching() {
        whisperModelStore.onReadyStateChanged = { [weak self] in
            self?.notifyMenuRebuild()
        }
        whisperModelStore.refreshReadyState()
        TapScribeStatusMenuController.shared.install()
        startTickTimer()

        guard !didRunLaunchCheck else { return }
        didRunLaunchCheck = true
        evaluateOnboardingPresentation()
    }

    func notifyMenuRebuild() {
        TapScribeStatusMenuController.shared.refresh()
    }

    /// Drives the elapsed time in the open menu. Added in `.common` mode so it also fires while the menu is tracking.
    private func startTickTimer() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isRecording || self.whisperModelStore.isBusy || self.isTranscribing {
                    self.notifyMenuRebuild()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func presentOnboarding() {
        NSApplication.shared.setActivationPolicy(.regular)
        OnboardingWindowPresenter.present(store: whisperModelStore) { [weak self] in
            self?.dismissOnboarding()
        }
    }

    func dismissOnboarding() {
        OnboardingWindowPresenter.dismiss()
        NSApplication.shared.setActivationPolicy(.accessory)
        whisperModelStore.refreshReadyState()
        if whisperModelStore.isReady {
            UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        }
        notifyMenuRebuild()
    }

    func prepareRedownloadOnboarding() {
        guard !isTranscribing else { return }
        whisperModelStore.cancelDownload()
        try? WhisperModelReadiness.removeCachedModels()
        whisperModelStore.refreshReadyState()
        UserDefaults.standard.set(false, forKey: Self.onboardingKey)
        notifyMenuRebuild()
        presentOnboarding()
    }

    private func evaluateOnboardingPresentation() {
        if whisperModelStore.isReady {
            UserDefaults.standard.set(true, forKey: Self.onboardingKey)
            return
        }
        presentOnboarding()
    }

    func toggleRecording() async {
        guard !isTogglingRecording else { return }
        isTogglingRecording = true
        notifyMenuRebuild()
        if isRecording {
            stopRecording()
        } else {
            await startRecording()
        }
        isTogglingRecording = false
        notifyMenuRebuild()
    }

    private func startRecording() async {
        let directory = RecordingsLocation.newSessionDirectory()
        do {
            try await session.start(in: directory)
            activeRecordingDirectory = directory
            recordingStartedAt = Date()
            isRecording = true
        } catch {
            presentRecordingStartError(error)
        }
    }

    private func stopRecording() {
        let directory = activeRecordingDirectory
        do {
            try session.stop()
        } catch {
            // Teardown errors do not invalidate what was already written to system.caf.
            logger.error("Recording stop reported: \(error.localizedDescription, privacy: .public)")
        }
        isRecording = false
        recordingStartedAt = nil
        activeRecordingDirectory = nil

        guard let directory else { return }
        if SessionRecordingDuration.isTooShortForTranscription(in: directory) {
            transcriptionStates[directory.path] = .skippedTooShort
        } else {
            enqueueTranscription(for: directory)
        }
    }

    func openRecordingFolder(_ url: URL) {
        RecordingsLocation.revealSessionFolder(url)
    }

    func quit() {
        transcriptionTask?.cancel()
        whisperModelStore.cancelDownload()
        if isRecording {
            try? session.stop()
        }
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Transcription

    /// Sessions are transcribed one at a time; a new recording never cancels earlier transcriptions.
    private func enqueueTranscription(for directory: URL) {
        transcriptionStates[directory.path] = .queued
        transcriptionQueue.append(directory)
        runNextTranscriptionIfIdle()
    }

    private func runNextTranscriptionIfIdle() {
        guard transcriptionTask == nil, !transcriptionQueue.isEmpty else { return }
        let directory = transcriptionQueue.removeFirst()
        transcriptionTask = Task {
            await transcribe(directory)
            transcriptionTask = nil
            notifyMenuRebuild()
            runNextTranscriptionIfIdle()
        }
    }

    private func transcribe(_ directory: URL) async {
        let key = directory.path
        whisperModelStore.refreshReadyState()
        guard whisperModelStore.isReady, !whisperModelStore.isBusy else {
            transcriptionStates[key] = .modelMissing
            return
        }

        transcriptionStates[key] = .running(detail: "przygotowanie…")
        notifyMenuRebuild()

        do {
            try await TranscriptionService.transcribeSession(at: directory) { message in
                Task { @MainActor in
                    let controller = TapScribeApplicationController.shared
                    guard case .running = controller.transcriptionStates[key] else { return }
                    controller.transcriptionStates[key] = .running(
                        detail: AppStatusText.polishTranscriptionDetail(from: message)
                    )
                }
            }
            transcriptionStates[key] = .succeeded
        } catch is CancellationError {
            transcriptionStates[key] = .cancelled
        } catch {
            transcriptionStates[key] = .failed(message: transcriptionErrorMessage(for: error))
            logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Errors

    private func presentRecordingStartError(_ error: Error) {
        logger.error("Recording start failed: \(error.localizedDescription, privacy: .public)")
        let permissionDenied: Bool
        if case let .systemAudio(underlying) = error as? RecordingSessionError,
           case .denied = underlying as? SystemAudioCaptureError {
            permissionDenied = true
        } else {
            permissionDenied = false
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Nie udało się rozpocząć nagrywania"
        alert.informativeText = error.localizedDescription
        if permissionDenied {
            alert.addButton(withTitle: "Otwórz Ustawienia")
            alert.addButton(withTitle: "Anuluj")
        } else {
            alert.addButton(withTitle: "OK")
        }
        if alert.runModal() == .alertFirstButtonReturn, permissionDenied {
            PrivacySettings.openSystemAudioRecording()
        }
    }

    private func transcriptionErrorMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
