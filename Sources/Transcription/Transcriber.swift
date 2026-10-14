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
        // Load after attaching the callback so callers see the loading phase.
        whisperKit.modelStateCallback = onModelState
        try await whisperKit.loadModels()
        return whisperKit
    }

    static func transcribe(path: URL) async throws -> [TranscriptSegment] {
        let whisperKit = try await makeWhisperKit()
        let decodeOptions = DecodingOptions(
            task: .transcribe,
            language: "pl",
            wordTimestamps: false,
            noSpeechThreshold: 0.6
        )
        return try await transcribeFile(path, whisperKit: whisperKit, decodeOptions: decodeOptions)
    }

    static func transcribeFile(
        _ path: URL,
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
            return mapSegments(transcriptions)
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
        // Folder names in argmaxinc/whisperkit-coreml are the variant names.
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
                    text: segment.text,
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
            "Brak pliku system.caf do transkrypcji."
        case let .whisperFailed(detail):
            "Transkrypcja nie powiodła się: \(detail)"
        }
    }
}
