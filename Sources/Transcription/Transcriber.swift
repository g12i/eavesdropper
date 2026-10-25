import Foundation
import WhisperKit

enum Transcriber {
    static let modelsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Eavesdropper/Models", isDirectory: true)
    }()

    typealias OnProgress = @Sendable (Double) -> Void

    static func makeWhisperKit(onModelState: ModelStateCallback? = nil) async throws -> WhisperKit {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let modelVariant = await preferredModelVariant()
        let localFolder = WhisperModelReadiness.localModelFolder()
        let config = WhisperKitConfig(
            model: modelVariant,
            downloadBase: modelsDirectory,
            modelFolder: localFolder?.path,
            verbose: false,
            logLevel: .info,
            prewarm: false,
            load: false,
            download: localFolder == nil,
            useBackgroundDownloadSession: false
        )

        let whisperKit = try await WhisperKit(config)
        whisperKit.modelStateCallback = onModelState
        try await whisperKit.loadModels()
        return whisperKit
    }

    static func transcribe(path: URL) async throws -> [TranscriptSegment] {
        let language = TranscriptionLanguage.stored
        let decodeOptions = decodingOptions(for: language)
        let whisperKit = try await makeWhisperKit()
        return try await transcribeFile(path, whisperKit: whisperKit, decodeOptions: decodeOptions, onProgress: nil)
    }

    static func transcribeFile(
        _ path: URL,
        whisperKit: WhisperKit,
        decodeOptions: DecodingOptions,
        onProgress: OnProgress? = nil
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
            onProgress?(1.0)
            return mapSegments(transcriptions)
        }
    }

    static func decodingOptions(for language: TranscriptionLanguage) -> DecodingOptions {
        switch language {
        case .polish:
            DecodingOptions(
                task: .transcribe,
                language: "pl",
                detectLanguage: false,
                wordTimestamps: false,
                noSpeechThreshold: 0.6
            )
        case .english:
            DecodingOptions(
                task: .transcribe,
                language: "en",
                detectLanguage: false,
                wordTimestamps: false,
                noSpeechThreshold: 0.6
            )
        case .auto:
            DecodingOptions(
                task: .transcribe,
                language: nil,
                detectLanguage: true,
                wordTimestamps: false,
                noSpeechThreshold: 0.6
            )
        }
    }

    private static let modelVariantKey = "whisperModelVariant"

    /// Variant resolved without network: env override, then the one pinned at download time.
    static var pinnedModelVariant: String? {
        if let env = ProcessInfo.processInfo.environment["TAPSCRIBE_WHISPER_MODEL"], !env.isEmpty {
            return env
        }
        return UserDefaults.standard.string(forKey: modelVariantKey)
    }

    /// Pinned so readiness checks stay offline and a changed remote default never triggers a surprise re-download.
    static func preferredModelVariant() async -> String {
        if let pinned = pinnedModelVariant {
            return pinned
        }
        if let local = WhisperModelReadiness.localModelFolder() {
            let variant = local.lastPathComponent
            UserDefaults.standard.set(variant, forKey: modelVariantKey)
            return variant
        }
        let remote = await WhisperKit.recommendedRemoteModels(downloadBase: modelsDirectory)
        UserDefaults.standard.set(remote.default, forKey: modelVariantKey)
        return remote.default
    }

    static func clearPinnedModelVariant() {
        UserDefaults.standard.removeObject(forKey: modelVariantKey)
    }

    private static func mapSegments(_ results: [TranscriptionResult]) -> [TranscriptSegment] {
        results.flatMap { result in
            result.segments.map { segment in
                TranscriptSegment(
                    start: TimeInterval(segment.start),
                    end: TimeInterval(segment.end),
                    text: TranscriptTextSanitizer.clean(segment.text),
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
            "No transcription result."
        case .noAudioFiles:
            "No system.caf file to transcribe."
        case let .whisperFailed(detail):
            "Transcription failed: \(detail)"
        }
    }
}
