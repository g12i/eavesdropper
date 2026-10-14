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
                            let fraction = progress.fractionCompleted
                            if fraction >= 1.0 {
                                self.downloadFraction = nil
                                self.statusLine = "Pliki pobrane. Ładowanie modelu…"
                            } else {
                                self.downloadFraction = fraction
                                let percent = Int(fraction * 100)
                                self.statusLine = "Pobieranie modelu… \(percent)%"
                            }
                            self.detailLine = self.polishProgressDetail(progress)
                        }
                    },
                    onModelState: { [weak self] _, newState in
                        Task { @MainActor in
                            guard let self else { return }
                            self.applyModelStateToUI(newState)
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

    private func applyModelStateToUI(_ state: ModelState) {
        let line = Self.polishModelState(state)
        detailLine = line
        switch state {
        case .downloading, .downloaded:
            break
        case .loading, .prewarming, .prewarmed, .unloading, .unloaded:
            downloadFraction = nil
            statusLine = line
        case .loaded:
            downloadFraction = nil
            statusLine = "Model gotowy."
        }
    }

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
