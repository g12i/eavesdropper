import Foundation
import WhisperKit

enum Transcriber {
    static let modelsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TapScribe/Models", isDirectory: true)
    }()

    static func makeWhisperKit(onModelState: ModelStateCallback? = nil) async throws -> WhisperKit {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let modelVariant = await preferredModelVariant()
        let config = WhisperKitConfig(
            model: modelVariant,
            downloadBase: modelsDirectory,
            modelFolder: nil,
            verbose: false,
            logLevel: .info,
            prewarm: false,
            load: true,
            download: true,
            useBackgroundDownloadSession: false
        )

        let whisperKit = try await WhisperKit(config)
        if let onModelState {
            whisperKit.modelStateCallback = onModelState
        }
        return whisperKit
    }

    static func transcribe(path: URL, speaker: TranscriptSpeaker) async throws -> [TranscriptSegment] {
        let whisperKit = try await makeWhisperKit()
        let decodeOptions = DecodingOptions(
            task: .transcribe,
            language: "pl",
            wordTimestamps: false,
            noSpeechThreshold: 0.6
        )
        return try await transcribeFile(path, speaker: speaker, whisperKit: whisperKit, decodeOptions: decodeOptions)
    }

    static func transcribeFile(
        _ path: URL,
        speaker: TranscriptSpeaker,
        whisperKit: WhisperKit,
        decodeOptions: DecodingOptions
    ) async throws -> [TranscriptSegment] {
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
            throw TranscriberError.whisperFailed(error.localizedDescription)
        case let .success(transcriptions):
            let elapsed = Date().timeIntervalSince(started)
            fputs("Transcription finished in \(String(format: "%.1f", elapsed))s\n", stderr)
            return mapSegments(transcriptions, speaker: speaker)
        }
    }

    static func preferredModelVariant() async -> String {
        if let env = ProcessInfo.processInfo.environment["TAPSCRIBE_WHISPER_MODEL"], !env.isEmpty {
            return env
        }
        let remote = await WhisperKit.recommendedRemoteModels(downloadBase: modelsDirectory)
        return remote.default
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
    case noAudioFiles
    case whisperFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyResult:
            "Brak wyniku transkrypcji."
        case .noAudioFiles:
            "Brak plików nagrania do transkrypcji."
        case let .whisperFailed(detail):
            "Transkrypcja nie powiodła się: \(detail)"
        }
    }
}
