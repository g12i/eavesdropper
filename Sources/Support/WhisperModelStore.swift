import Foundation
import SwiftUI
import WhisperKit

@MainActor
final class WhisperModelStore: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    @Published var statusLine = "Sprawdzanie modelu…"
    @Published var detailLine = ""
    @Published var downloadFraction: Double?

    private var downloadTask: Task<Void, Never>?

    func refreshReadyState() async {
        isReady = await WhisperModelReadiness.isModelPresentOnDisk()
        if isReady {
            statusLine = "Model transkrypcji jest gotowy."
            detailLine = ""
            downloadFraction = nil
        } else {
            statusLine = "Transkrypcja wymaga pobrania modelu (~1,5 GB)."
            detailLine = "Nagrywanie dźwięku systemu działa od razu; transkrypt pojawi się po pobraniu modelu."
        }
    }

    func startDownload(forceRedownload: Bool = false) {
        guard !isBusy else { return }
        downloadTask?.cancel()

        downloadTask = Task {
            isBusy = true
            downloadFraction = nil
            statusLine = forceRedownload ? "Usuwanie starego modelu…" : "Przygotowanie pobierania…"
            detailLine = ""

            do {
                if forceRedownload {
                    try WhisperModelReadiness.removeCachedModels()
                }

                try await WhisperModelReadiness.downloadAndPrepare(
                    onProgress: { [weak self] progress in
                        Task { @MainActor in
                            guard let self else { return }
                            self.downloadFraction = progress.fractionCompleted
                            let percent = Int(progress.fractionCompleted * 100)
                            self.statusLine = "Pobieranie modelu… \(percent)%"
                            self.detailLine = self.polishProgressDetail(progress)
                        }
                    },
                    onModelState: { [weak self] _, newState in
                        Task { @MainActor in
                            self?.detailLine = Self.polishModelState(newState)
                        }
                    }
                )

                isReady = true
                downloadFraction = 1
                statusLine = "Model gotowy. Możesz nagrywać i transkrybować."
                detailLine = ""
                UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
            } catch is CancellationError {
                statusLine = "Pobieranie anulowane."
                await refreshReadyState()
            } catch {
                isReady = false
                statusLine = "Nie udało się pobrać modelu."
                detailLine = error.localizedDescription
            }

            isBusy = false
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isBusy = false
    }

    static let onboardingCompletedKey = "whisperOnboardingCompleted"

    private static func polishModelState(_ state: ModelState) -> String {
        switch state {
        case .downloading, .downloaded:
            "Pobieranie plików modelu…"
        case .loading, .prewarming, .prewarmed:
            "Ładowanie modelu do pamięci…"
        case .loaded:
            "Model załadowany."
        case .unloading, .unloaded:
            "Przygotowanie…"
        }
    }

    private func polishProgressDetail(_ progress: Progress) -> String {
        if let file = progress.fileURL?.lastPathComponent, !file.isEmpty {
            return file
        }
        if progress.totalUnitCount > 0 {
            let done = progress.completedUnitCount
            let total = progress.totalUnitCount
            return "\(done) / \(total)"
        }
        return "Trwa pobieranie…"
    }
}
