import Foundation
import AppKit
import OSLog

@MainActor
final class TranscriptionDialogModel: ObservableObject {
    @Published private(set) var state: SessionTranscriptionState
    @Published var selectedLanguage: TranscriptionLanguage
    @Published private(set) var detectedLanguage: String?
    @Published private(set) var audioSeconds: Double = 0
    @Published private(set) var queuePosition: Int?
    @Published private(set) var isModelReady: Bool = false
    @Published private(set) var modelStatus: String = ""

    private let sessionURL: URL
    private let service = TranscriptionService.shared
    private let modelStore = WhisperModelStore()
    private let logger = Logger(subsystem: "com.eavesdropper.app", category: "TranscriptionDialog")
    private var refreshTimer: Timer?

    init(sessionURL: URL) {
        self.sessionURL = sessionURL
        self.state = service.state(for: sessionURL)
        self.selectedLanguage = TranscriptionLanguage.stored
        self.isModelReady = modelStore.isReady
        self.modelStatus = modelStore.statusLine

        loadAudioDuration()
        startRefreshTimer()
    }

    private func startRefreshTimer() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.state = self.service.state(for: self.sessionURL)
                self.queuePosition = self.service.queuePosition(for: self.sessionURL)
                self.isModelReady = self.modelStore.isReady
                self.modelStatus = self.modelStore.statusLine
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.refreshTimer = timer
    }

    private func loadAudioDuration() {
        if let seconds = SessionRecordingDuration.durationSeconds(in: sessionURL) {
            audioSeconds = seconds
        }
    }

    func transcribe() {
        selectedLanguage.save()
        service.transcribe(session: sessionURL, language: selectedLanguage)
    }

    func cancel() {
        service.cancel(session: sessionURL)
    }

    func openInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([sessionURL])
    }

    func openTranscript() {
        let transcriptURL = sessionURL.appendingPathComponent("transcript.txt")
        NSWorkspace.shared.open(transcriptURL)
    }

    func presentOnboarding() {
        NSApplication.shared.setActivationPolicy(.regular)
        OnboardingWindowPresenter.present(store: modelStore) { [weak self] in
            self?.dismissOnboarding()
        }
    }

    func dismissOnboarding() {
        OnboardingWindowPresenter.dismiss()
        NSApplication.shared.setActivationPolicy(.accessory)
        modelStore.refreshReadyState()
    }

    var isShortRecording: Bool {
        TranscriptionPolicy.isShort(duration: audioSeconds)
    }

    var isTranscribeDisabled: Bool {
        switch state {
        case .transcribing, .loadingModel, .cancelling:
            return true
        default:
            return !isModelReady || audioSeconds == 0
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }
}
