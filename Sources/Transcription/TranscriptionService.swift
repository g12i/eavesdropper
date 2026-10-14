import Foundation
import WhisperKit

enum TranscriptionService {
    typealias StatusHandler = @Sendable (String) -> Void

    static func transcribeSession(at directory: URL, onStatus: StatusHandler? = nil) async throws {
        let systemPath = directory.appendingPathComponent("system.caf")

        guard FileManager.default.fileExists(atPath: systemPath.path) else {
            throw TranscriberError.noAudioFiles
        }

        onStatus?("Transkrypcja: ładowanie modelu…")

        let whisperKit = try await Transcriber.makeWhisperKit { _, newState in
            onStatus?(polishStatus(for: newState))
        }

        let decodeOptions = DecodingOptions(
            task: .transcribe,
            language: "pl",
            wordTimestamps: false,
            noSpeechThreshold: 0.6
        )

        onStatus?("Transkrypcja: dźwięk systemu…")
        let segments = try await Transcriber.transcribeFile(
            systemPath,
            whisperKit: whisperKit,
            decodeOptions: decodeOptions
        )

        let merged = TranscriptMerger.merge(segments)
        try TranscriptMerger.writeTXT(merged, to: directory.appendingPathComponent("transcript.txt"))
        try TranscriptMerger.writeSRT(merged, to: directory.appendingPathComponent("transcript.srt"))
    }

    private static func polishStatus(for state: ModelState) -> String {
        switch state {
        case .downloading, .downloaded:
            "Transkrypcja: pobieranie modelu…"
        case .loading, .prewarming, .prewarmed:
            "Transkrypcja: ładowanie modelu…"
        case .loaded:
            "Transkrypcja: rozpoznawanie mowy…"
        case .unloading, .unloaded:
            "Transkrypcja: przygotowanie…"
        }
    }
}
