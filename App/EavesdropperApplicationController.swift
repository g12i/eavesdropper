import AppKit
import Foundation
import OSLog

@MainActor
final class EavesdropperApplicationController: ObservableObject {
    static let shared = EavesdropperApplicationController()

    let whisperModelStore = WhisperModelStore()

    @Published private(set) var isRecording = false
    /// True while start/stop is in flight (e.g. the TCC prompt is up); blocks double toggles.
    @Published private(set) var isTogglingRecording = false
    private(set) var recordingStartedAt: Date?
    private(set) var activeRecordingDirectory: URL?
    private let session = RecordingSession()

    /// Per-session transcription phase for this app run, keyed by session folder path.
    @Published private(set) var transcriptionStates: [String: TranscriptionPhase] = [:]
    private var tickTimer: Timer?
    private var didRunLaunchCheck = false

    private let logger = Logger(subsystem: "com.eavesdropper.app", category: "EavesdropperApplicationController")
    private static let onboardingKey = WhisperModelStore.onboardingCompletedKey

    private init() {}

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
        EavesdropperStatusMenuController.shared.install()
        startTickTimer()

        guard !didRunLaunchCheck else { return }
        didRunLaunchCheck = true
        evaluateOnboardingPresentation()
    }

    func notifyMenuRebuild() {
        EavesdropperStatusMenuController.shared.refresh()
    }

    /// Drives the elapsed time in the open menu. Added in `.common` mode so it also fires while the menu is tracking.
    private func startTickTimer() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isRecording || self.whisperModelStore.isBusy {
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
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Re-download transcription model?"
        alert.informativeText = "The current model (~1.5 GB) will be deleted. This helps if transcription reports model errors. Recording works without a model."
        alert.addButton(withTitle: "Delete and Download")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

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
            logger.error("Recording stop reported: \(error.localizedDescription, privacy: .public)")
        }
        isRecording = false
        recordingStartedAt = nil
        activeRecordingDirectory = nil

        guard let directory else { return }
        transcriptionStates[directory.path] = .idle
    }

    func openRecordingFolder(_ url: URL) {
        RecordingsLocation.revealSessionFolder(url)
    }

    func quit() {
        whisperModelStore.cancelDownload()
        if isRecording {
            try? session.stop()
        }
        NSApplication.shared.terminate(nil)
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
        alert.messageText = "Failed to start recording"
        alert.informativeText = error.localizedDescription
        if permissionDenied {
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
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
