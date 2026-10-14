import AppKit
import Foundation
import OSLog

struct SessionMetadata: Codable {
    let systemStartHostTime: UInt64?
    let micStartHostTime: UInt64?
    let startedAt: Date
    let recordMicrophone: Bool
}

final class RecordingSession {
    private let systemTap = SystemAudioTap()
    private let micRecorder = MicRecorder()
    private(set) var outputDirectory: URL?
    private let logger = Logger(subsystem: "com.tapscribe.app", category: "RecordingSession")

    var isRecording: Bool { systemTap.isRunning }

    /// Primary path: system audio (process tap). Microphone is optional.
    func start(in directory: URL, recordMicrophone: Bool) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        outputDirectory = directory

        activateForCapture()

        var systemStarted = false
        do {
            try SystemAudioCapturePermission.ensureAuthorized()
            let systemURL = directory.appendingPathComponent("system.caf")
            try systemTap.start(writingTo: systemURL)
            systemStarted = true
            logger.info("System audio tap started")

            if recordMicrophone {
                do {
                    try MicrophonePermission.ensureAuthorized()
                    let micURL = directory.appendingPathComponent("mic.caf")
                    try micRecorder.start(writingTo: micURL)
                    logger.info("Microphone recording started")
                } catch {
                    throw RecordingSessionError.microphone(underlying: error)
                }
            }

            let meta = SessionMetadata(
                systemStartHostTime: mach_absolute_time(),
                micStartHostTime: recordMicrophone ? micRecorder.startHostTime : nil,
                startedAt: Date(),
                recordMicrophone: recordMicrophone
            )
            let data = try JSONEncoder().encode(meta)
            try data.write(to: directory.appendingPathComponent("session.json"))
        } catch let sessionError as RecordingSessionError {
            logger.error("Recording start failed (\(sessionError.failurePhase)): \(sessionError.localizedDescription, privacy: .public)")
            rollback(systemStarted: systemStarted)
            throw sessionError
        } catch {
            logger.error("Recording start failed (system): \(error.localizedDescription, privacy: .public)")
            rollback(systemStarted: systemStarted)
            throw RecordingSessionError.systemAudio(underlying: error)
        }
    }

    func stop() throws {
        try systemTap.stop()
        micRecorder.stop()
    }

    func systemAudioURL() -> URL? {
        outputDirectory?.appendingPathComponent("system.caf")
    }

    func micAudioURL() -> URL? {
        outputDirectory?.appendingPathComponent("mic.caf")
    }

    private func rollback(systemStarted: Bool) {
        if systemStarted {
            try? systemTap.stop()
        }
        micRecorder.stop()
        outputDirectory = nil
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
