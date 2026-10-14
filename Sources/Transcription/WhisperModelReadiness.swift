import Foundation
import WhisperKit

enum WhisperModelReadiness {
    typealias ProgressHandler = @Sendable (Progress) -> Void

    /// Finds a folder under `Transcriber.modelsDirectory` that contains Whisper Core ML weights.
    static func localModelFolder() async -> URL? {
        let base = Transcriber.modelsDirectory
        guard FileManager.default.fileExists(atPath: base.path) else {
            return nil
        }

        let variant = await Transcriber.preferredModelVariant()
        if let direct = folderContainingMelSpectrogram(startingAt: base, preferNameContains: variant) {
            return direct
        }
        return folderContainingMelSpectrogram(startingAt: base, preferNameContains: nil)
    }

    static func isModelPresentOnDisk() async -> Bool {
        await localModelFolder() != nil
    }

    static func downloadAndPrepare(
        onProgress: ProgressHandler? = nil,
        onModelState: ModelStateCallback? = nil
    ) async throws {
        let variant = await Transcriber.preferredModelVariant()
        let folder = try await WhisperKit.download(
            variant: variant,
            downloadBase: Transcriber.modelsDirectory,
            progressCallback: { progress in
                onProgress?(progress)
            }
        )

        let config = WhisperKitConfig(
            model: variant,
            downloadBase: Transcriber.modelsDirectory,
            modelFolder: folder.path,
            verbose: false,
            logLevel: .info,
            prewarm: false,
            load: true,
            download: false,
            useBackgroundDownloadSession: false
        )

        let whisperKit = try await WhisperKit(config)
        if let onModelState {
            whisperKit.modelStateCallback = onModelState
        }
        if whisperKit.modelState != .loaded {
            try await whisperKit.loadModels()
        }
    }

    static func removeCachedModels() throws {
        let base = Transcriber.modelsDirectory
        if FileManager.default.fileExists(atPath: base.path) {
            try FileManager.default.removeItem(at: base)
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private static func folderContainingMelSpectrogram(startingAt root: URL, preferNameContains: String?) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var matches: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix("MelSpectrogram"), name.hasSuffix(".mlmodelc") || name.hasSuffix(".mlpackage") else {
                continue
            }
            let folder = url.deletingLastPathComponent()
            if folder.path.contains("/.cache/") {
                continue
            }
            matches.append(folder)
        }

        if matches.isEmpty {
            return nil
        }

        if let preferNameContains, !preferNameContains.isEmpty {
            if let preferred = matches.first(where: { $0.path.localizedCaseInsensitiveContains(preferNameContains) }) {
                return preferred
            }
        }

        return matches.sorted { $0.path > $1.path }.first
    }
}
