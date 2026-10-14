import Foundation
import OSLog

struct SessionMetadata: Codable {
    let systemStartHostTime: UInt64?
    let startedAt: Date
}

final class RecordingSession {
    private let systemTap = SystemAudioTap()
    private(set) var outputDirectory: URL?
    private let logger = Logger(subsystem: "com.tapscribe.app", category: "RecordingSession")

    var isRecording: Bool { systemTap.isRunning }

    func start(in directory: URL) async throws {
        let createdDirectory = !FileManager.default.fileExists(atPath: directory.path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            try await SystemAudioCapturePermission.ensureAuthorized()
            let systemURL = directory.appendingPathComponent("system.caf")
            try systemTap.start(writingTo: systemURL)
            logger.info("System audio tap started")

            let meta = SessionMetadata(
                systemStartHostTime: mach_absolute_time(),
                startedAt: Date()
            )
            let data = try JSONEncoder().encode(meta)
            try data.write(to: directory.appendingPathComponent("session.json"))
            outputDirectory = directory
        } catch {
            logger.error("Recording start failed (system): \(error.localizedDescription, privacy: .public)")
            try? systemTap.stop()
            outputDirectory = nil
            if createdDirectory {
                try? FileManager.default.removeItem(at: directory)
            }
            throw RecordingSessionError.systemAudio(underlying: error)
        }
    }

    func stop() throws {
        defer { outputDirectory = nil }
        try systemTap.stop()
    }

    func systemAudioURL() -> URL? {
        outputDirectory?.appendingPathComponent("system.caf")
    }
}
