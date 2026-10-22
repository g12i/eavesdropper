import Foundation
import SwiftUI
import WhisperKit

@MainActor
final class WhisperModelStore: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    /// True after files are on disk while WhisperKit compiles/loads the model (can take minutes on first run).
    @Published private(set) var isLoadingModel = false
    @Published var statusLine = "Checking model…"
    @Published var detailLine = ""
    @Published var downloadFraction: Double?

    private var downloadTask: Task<Void, Never>?
    private var downloadGeneration = 0
    var onReadyStateChanged: (() -> Void)?

    static let onboardingCompletedKey = "whisperOnboardingCompleted"

    /// No-op while a download runs: the partially downloaded folder would look ready and the
    /// "requires download" copy would overwrite live progress.
    func refreshReadyState() {
        guard !isBusy else { return }
        isReady = WhisperModelReadiness.isModelPresentOnDisk()
        if isReady {
            statusLine = "Transcription model ready."
            detailLine = ""
            downloadFraction = nil
        } else {
            statusLine = "Transcription requires model download (~1.5 GB)."
            detailLine = "System audio recording works immediately; transcripts appear after model downloads."
        }
    }

    func startDownload(forceRedownload: Bool = false) {
        guard !isBusy else { return }
        downloadTask?.cancel()
        downloadGeneration += 1
        let generation = downloadGeneration

        isBusy = true
        isReady = false
        isLoadingModel = false
        downloadFraction = nil
        statusLine = forceRedownload ? "Removing old model…" : "Preparing download…"
        detailLine = ""
        onReadyStateChanged?()

        downloadTask = Task {
            do {
                if forceRedownload {
                    try WhisperModelReadiness.removeCachedModels()
                }

                try await WhisperModelReadiness.downloadAndPrepare(
                    onProgress: { [weak self] progress in
                        Task { @MainActor in
                            self?.applyDownloadProgress(progress, generation: generation)
                        }
                    },
                    onDownloadFinished: { [weak self] in
                        Task { @MainActor in
                            self?.enterLoadingPhase(generation: generation)
                        }
                    },
                    onModelState: { [weak self] _, newState in
                        Task { @MainActor in
                            self?.applyModelState(newState, generation: generation)
                        }
                    }
                )
                guard generation == downloadGeneration else { return }
                isReady = true
                finishDownload()
                statusLine = "Model ready. You can record and transcribe."
                detailLine = ""
                UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
            } catch is CancellationError {
                guard generation == downloadGeneration else { return }
                finishDownload()
                refreshReadyState()
                statusLine = "Download cancelled."
            } catch {
                guard generation == downloadGeneration else { return }
                finishDownload()
                isReady = false
                statusLine = "Failed to download model."
                detailLine = error.localizedDescription
            }
            onReadyStateChanged?()
        }
    }

    func cancelDownload() {
        guard isBusy else { return }
        downloadTask?.cancel()
        downloadTask = nil
        downloadGeneration += 1
        finishDownload()
        refreshReadyState()
        statusLine = "Download cancelled."
        onReadyStateChanged?()
    }

    private func finishDownload() {
        isBusy = false
        isLoadingModel = false
        downloadFraction = nil
    }

    private func applyDownloadProgress(_ progress: Progress, generation: Int) {
        guard generation == downloadGeneration, isBusy, !isLoadingModel else { return }
        let fraction = min(max(progress.fractionCompleted, 0), 1)
        downloadFraction = fraction
        statusLine = "Downloading model… \(Int(fraction * 100))%"
        detailLine = progressDetail(progress)
        onReadyStateChanged?()
    }

    private func enterLoadingPhase(generation: Int) {
        guard generation == downloadGeneration, isBusy, !isLoadingModel else { return }
        isLoadingModel = true
        downloadFraction = nil
        statusLine = "Files downloaded. Loading model…"
        detailLine = "First load optimizes the model for this Mac and may take several minutes."
        onReadyStateChanged?()
    }

    private func applyModelState(_ state: ModelState, generation: Int) {
        guard generation == downloadGeneration, isBusy else { return }
        switch state {
        case .loading, .prewarming, .prewarmed:
            enterLoadingPhase(generation: generation)
            statusLine = "Loading model into memory…"
        case .downloading, .downloaded, .loaded, .unloading, .unloaded:
            break
        }
    }

    private func progressDetail(_ progress: Progress) -> String {
        if let file = progress.fileURL?.lastPathComponent, !file.isEmpty {
            return file
        }
        if progress.totalUnitCount > 0 {
            // Hub snapshot progress counts files, not bytes.
            return "File \(progress.completedUnitCount) of \(progress.totalUnitCount)"
        }
        return "Downloading…"
    }
}
