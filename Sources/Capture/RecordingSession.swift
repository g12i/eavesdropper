import AppKit
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

    func start(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        outputDirectory = directory

        activateForCapture()

        do {
            try SystemAudioCapturePermission.ensureAuthorized()
            let systemURL = directory.appendingPathComponent("system.caf")
            try systemTap.start(writingTo: systemURL)
            logger.info("System audio tap started")

            let meta = SessionMetadata(
                systemStartHostTime: mach_absolute_time(),
                startedAt: Date()
            )
            let data = try JSONEncoder().encode(meta)
            try data.write(to: directory.appendingPathComponent("session.json"))
        } catch {
            logger.error("Recording start failed (system): \(error.localizedDescription, privacy: .public)")
            try? systemTap.stop()
            outputDirectory = nil
            throw RecordingSessionError.systemAudio(underlying: error)
        }
    }

    func stop() throws {
        try systemTap.stop()
    }

    func systemAudioURL() -> URL? {
        outputDirectory?.appendingPathComponent("system.caf")
    }

    private func activateForCapture() {
        let activate = { NSApplication.shared.activate(ignoringOtherApps: true) }
        if Thread.isMainThread {
            activate()
        } else {
            DispatchQueue.main.sync(execute: activate)
        }
    }
}
