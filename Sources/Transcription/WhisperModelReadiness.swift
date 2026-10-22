import Foundation
import WhisperKit

enum WhisperModelReadiness {
    typealias ProgressHandler = @Sendable (Progress) -> Void

    /// Finds a folder under `Transcriber.modelsDirectory` that contains Whisper Core ML weights.
    /// Filesystem only (no network), cheap enough to call on the main thread when the menu opens.
    /// Falls back to legacy `TapScribe/Models` path for one-time migration.
    static func localModelFolder() -> URL? {
        let base = Transcriber.modelsDirectory
        if FileManager.default.fileExists(atPath: base.path) {
            if let found = folderContainingMelSpectrogram(startingAt: base, preferNameContains: Transcriber.pinnedModelVariant) {
                return found
            }
        }
        
        // Fallback: check legacy TapScribe path
        let legacyBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TapScribe/Models", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacyBase.path) {
            return folderContainingMelSpectrogram(startingAt: legacyBase, preferNameContains: Transcriber.pinnedModelVariant)
        }
        
        return nil
    }

    static func isModelPresentOnDisk() -> Bool {
        localModelFolder() != nil
    }

    /// Downloads the model, then loads it once so the slow first Core ML compile happens during onboarding.
    static func downloadAndPrepare(
        onProgress: ProgressHandler? = nil,
        onDownloadFinished: (@Sendable () -> Void)? = nil,
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
        try Task.checkCancellation()
        onDownloadFinished?()

        let config = WhisperKitConfig(
            model: variant,
            downloadBase: Transcriber.modelsDirectory,
            modelFolder: folder.path,
            verbose: false,
            logLevel: .info,
            prewarm: false,
            load: false,
            download: false,
            useBackgroundDownloadSession: false
        )

        let whisperKit = try await WhisperKit(config)
        whisperKit.modelStateCallback = onModelState
        try await whisperKit.loadModels()
    }

    static func removeCachedModels() throws {
        Transcriber.clearPinnedModelVariant()
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
            let isModelBundle = name.hasSuffix(".mlmodelc") || name.hasSuffix(".mlpackage")
            if isModelBundle {
                enumerator.skipDescendants()
            }
            guard name.hasPrefix("MelSpectrogram"), isModelBundle else {
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
