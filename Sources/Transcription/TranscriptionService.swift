import Foundation
import WhisperKit
import OSLog

@MainActor
final class TranscriptionService: ObservableObject {
    @Published private(set) var states: [String: SessionTranscriptionState] = [:]
    
    private var transcriptionQueue: [TranscriptionTask] = []
    private var transcriptionTask: Task<Void, Never>?
    private var whisperKitInstance: WhisperKit?
    private let logger = Logger(subsystem: "com.eavesdropper.app", category: "TranscriptionService")

    static let shared = TranscriptionService()

    private init() {
        loadInitialStates()
    }

    func state(for session: URL) -> SessionTranscriptionState {
        states[session.path] ?? .idle(hasTranscript: SessionTranscriptionState.hasTranscriptOnDisk(session))
    }

    func queuePosition(for session: URL) -> Int? {
        transcriptionQueue.firstIndex(where: { $0.sessionURL.path == session.path })
    }

    func transcribe(session: URL, language: TranscriptionLanguage) {
        let key = session.path
        let currentState = state(for: session)

        switch currentState {
        case .transcribing, .loadingModel, .cancelling:
            logger.info("Transcription already in progress for \(key)")
            return
        default:
            break
        }

        let task = TranscriptionTask(sessionURL: session, language: language)
        states[key] = .queued(language: language)
        transcriptionQueue.append(task)
        processNextIfIdle()
    }

    func cancel(session: URL) {
        let key = session.path

        switch states[key] {
        case .queued(let language):
            if let index = transcriptionQueue.firstIndex(where: { $0.sessionURL.path == key }) {
                transcriptionQueue.remove(at: index)
            }
            let hadTranscript = didHaveTranscriptBefore(key)
            states[key] = hadTranscript ? .done(detectedLanguage: nil) : .idle(hasTranscript: false)

        case .transcribing(let language, _), .loadingModel(let language):
            states[key] = .cancelling
            transcriptionTask?.cancel()

        case .cancelling:
            break

        default:
            break
        }
    }

    private func processNextIfIdle() {
        guard transcriptionTask == nil, !transcriptionQueue.isEmpty else { return }
        let task = transcriptionQueue.removeFirst()
        transcriptionTask = Task {
            await performTranscription(task)
            self.transcriptionTask = nil
            self.processNextIfIdle()
        }
    }

    private func performTranscription(_ task: TranscriptionTask) async {
        let key = task.sessionURL.path

        guard FileManager.default.fileExists(atPath: task.sessionURL.appendingPathComponent("system.caf").path) else {
            states[key] = .failed(message: "Brak pliku audio do transkrypcji.")
            return
        }

        do {
            states[key] = .loadingModel(language: task.language)

            let whisperKit = try await getOrCreateWhisperKit()
            
            try Task.checkCancellation()
            
            states[key] = .transcribing(language: task.language, fraction: 0)

            let decodeOptions = Transcriber.decodingOptions(for: task.language)
            let audioPath = task.sessionURL.appendingPathComponent("system.caf")
            
            var lastProgressUpdate = Date()
            var lastReportedPercentage = 0
            let segments = try await Transcriber.transcribeFile(
                audioPath,
                whisperKit: whisperKit,
                decodeOptions: decodeOptions,
                onProgress: { [weak self] progress in
                    let now = Date()
                    if now.timeIntervalSince(lastProgressUpdate) >= 0.5 {
                        let percentage = Int(progress * 100)
                        if percentage > lastReportedPercentage {
                            Task { @MainActor in
                                self?.states[key] = .transcribing(language: task.language, fraction: progress)
                            }
                            lastReportedPercentage = percentage
                            lastProgressUpdate = now
                        }
                    }
                }
            )

            try Task.checkCancellation()

            let merged = TranscriptMerger.merge(segments)
            let transcriptURL = task.sessionURL.appendingPathComponent("transcript.txt")
            let srtURL = task.sessionURL.appendingPathComponent("transcript.srt")

            let tmpTxt = transcriptURL.appendingPathExtension("tmp")
            let tmpSrt = srtURL.appendingPathExtension("tmp")

            try TranscriptMerger.writeTXT(merged, to: tmpTxt)
            try TranscriptMerger.writeSRT(merged, to: tmpSrt)

            try FileManager.default.replaceItemAt(
                transcriptURL,
                withItemAt: tmpTxt,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
            try FileManager.default.replaceItemAt(
                srtURL,
                withItemAt: tmpSrt,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )

            let detectedLanguage: String? = nil
            writeTranscriptionMetadata(
                to: task.sessionURL,
                language: task.language.rawValue,
                detectedLanguage: detectedLanguage,
                audioSeconds: Double(segments.map { $0.end }.max() ?? 0)
            )

            states[key] = .done(detectedLanguage: detectedLanguage)
        } catch is CancellationError {
            let hadTranscript = didHaveTranscriptBefore(key)
            states[key] = hadTranscript ? .done(detectedLanguage: nil) : .idle(hasTranscript: false)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            states[key] = .failed(message: message)
            logger.error("Transcription failed: \(message)")
        }
    }

    private func getOrCreateWhisperKit() async throws -> WhisperKit {
        if let existing = whisperKitInstance {
            return existing
        }
        let kit = try await Transcriber.makeWhisperKit()
        whisperKitInstance = kit
        return kit
    }

    private func loadInitialStates() {
        let recentSessions = RecordingsIndex.recent(limit: 50)
        for entry in recentSessions {
            let key = entry.url.path
            let transcriptExists = FileManager.default.fileExists(atPath: entry.url.appendingPathComponent("transcript.txt").path)
            
            if transcriptExists {
                states[key] = .done(detectedLanguage: nil)
            } else if let failedData = readTranscriptionMetadata(from: entry.url), failedData["status"] == "failed" {
                states[key] = .failed(message: failedData["message"] ?? "Błąd transkrypcji.")
            } else {
                states[key] = .idle(hasTranscript: false)
            }
        }

        cleanupTemporaryFiles()
    }

    private func didHaveTranscriptBefore(_ key: String) -> Bool {
        if case .done = states[key] {
            return true
        }
        return false
    }

    private func writeTranscriptionMetadata(
        to sessionDir: URL,
        language: String,
        detectedLanguage: String?,
        audioSeconds: Double
    ) {
        let metadata: [String: Any] = [
            "language": language,
            "detectedLanguage": detectedLanguage ?? NSNull(),
            "model": Transcriber.pinnedModelVariant ?? "unknown",
            "finishedAt": ISO8601DateFormatter().string(from: Date()),
            "audioSeconds": audioSeconds,
        ]

        let metadataURL = sessionDir.appendingPathComponent("transcription.json")
        try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted).write(to: metadataURL)
    }

    private func readTranscriptionMetadata(from sessionDir: URL) -> [String: String]? {
        let metadataURL = sessionDir.appendingPathComponent("transcription.json")
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }

    private func cleanupTemporaryFiles() {
        let fm = FileManager.default
        let recentSessions = RecordingsIndex.recent(limit: 100)
        for entry in recentSessions {
            do {
                let files = try fm.contentsOfDirectory(at: entry.url, includingPropertiesForKeys: nil)
                for file in files where file.lastPathComponent.hasSuffix(".tmp") {
                    try fm.removeItem(at: file)
                }
            } catch {
                logger.debug("Cleanup error: \(error.localizedDescription)")
            }
        }
    }
}

extension SessionTranscriptionState {
    static func hasTranscriptOnDisk(_ session: URL) -> Bool {
        FileManager.default.fileExists(atPath: session.appendingPathComponent("transcript.txt").path)
    }
}
