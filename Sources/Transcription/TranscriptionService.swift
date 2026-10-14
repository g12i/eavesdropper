import Foundation
import WhisperKit

enum TranscriptionService {
    typealias StatusHandler = @Sendable (String) -> Void

    static func transcribeSession(at directory: URL, onStatus: StatusHandler? = nil) async throws {
        let micPath = directory.appendingPathComponent("mic.caf")
        let systemPath = directory.appendingPathComponent("system.caf")

        guard FileManager.default.fileExists(atPath: systemPath.path)
            || FileManager.default.fileExists(atPath: micPath.path)
        else {
            throw TranscriberError.noAudioFiles
        }

        onStatus?("Transkrypcja: pobieranie modelu…")

        let whisperKit = try await Transcriber.makeWhisperKit { _, newState in
            onStatus?(polishStatus(for: newState))
        }

        var mic: [TranscriptSegment] = []
        var system: [TranscriptSegment] = []

        let decodeOptions = DecodingOptions(
            task: .transcribe,
            language: "pl",
            wordTimestamps: false,
            noSpeechThreshold: 0.6
        )

        if FileManager.default.fileExists(atPath: micPath.path) {
            onStatus?("Transkrypcja: ścieżka „Ja”…")
            mic = try await Transcriber.transcribeFile(micPath, speaker: .me, whisperKit: whisperKit, decodeOptions: decodeOptions)
        }
        if FileManager.default.fileExists(atPath: systemPath.path) {
            onStatus?("Transkrypcja: dźwięk systemu (Rozmówcy)…")
            system = try await Transcriber.transcribeFile(
                systemPath,
                speaker: .others,
                whisperKit: whisperKit,
                decodeOptions: decodeOptions
            )
        }

        let merged = TranscriptMerger.merge(micSegments: mic, systemSegments: system)
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
