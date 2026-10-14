import Foundation
import WhisperKit

enum Transcriber {
    private static let modelsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TapScribe/Models", isDirectory: true)
    }()

    static func transcribe(path: URL, speaker: TranscriptSpeaker) async throws -> [TranscriptSegment] {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let modelName = preferredModelName()
        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelsDirectory.path,
            verbose: false,
            logLevel: .info,
            prewarm: false,
            load: true,
            useBackgroundDownloadSession: false
        )

        let whisperKit = try await WhisperKit(config)
        let decodeOptions = DecodingOptions(
            task: .transcribe,
            language: "pl",
            wordTimestamps: false,
            noSpeechThreshold: 0.6
        )

        let started = Date()
        let results = await whisperKit.transcribeWithResults(
            audioPaths: [path.path],
            decodeOptions: decodeOptions
        )

        guard let first = results.first else {
            throw TranscriberError.emptyResult
        }
        switch first {
        case let .failure(error):
            throw error
        case let .success(transcriptions):
            let elapsed = Date().timeIntervalSince(started)
            fputs("Transcription finished in \(String(format: "%.1f", elapsed))s\n", stderr)
            return mapSegments(transcriptions, speaker: speaker)
        }
    }

    static func preferredModelName() -> String? {
        if let env = ProcessInfo.processInfo.environment["TAPSCRIBE_WHISPER_MODEL"], !env.isEmpty {
            return env
        }
        let recommended = WhisperKit.recommendedModels()
        if recommended.default.contains("large") {
            return recommended.default
        }
        return "openai_whisper-large-v3_turbo"
    }

    private static func mapSegments(_ results: [TranscriptionResult], speaker: TranscriptSpeaker) -> [TranscriptSegment] {
        results.flatMap { result in
            result.segments.map { segment in
                TranscriptSegment(
                    start: TimeInterval(segment.start),
                    end: TimeInterval(segment.end),
                    text: segment.text,
                    speaker: speaker,
                    noSpeechProb: segment.noSpeechProb
                )
            }
        }
    }
}

enum TranscriberError: LocalizedError {
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .emptyResult:
            "Brak wyniku transkrypcji."
        }
    }
}
