import AppKit
import Foundation
import OSLog

struct SessionMetadata: Codable {
    let systemStartHostTime: UInt64?
    let micStartHostTime: UInt64?
    let startedAt: Date
}

final class RecordingSession {
    private let systemTap = SystemAudioTap()
    private let micRecorder = MicRecorder()
    private(set) var outputDirectory: URL?
    private let logger = Logger(subsystem: "com.tapscribe.app", category: "RecordingSession")

    var isRecording: Bool { systemTap.isRunning }

    func start(in directory: URL, recordMicrophone: Bool) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        outputDirectory = directory

        activateForCapture()

        var micStarted = false
        do {
            if recordMicrophone {
                try MicrophonePermission.ensureAuthorized()
                let micURL = directory.appendingPathComponent("mic.caf")
                try micRecorder.start(writingTo: micURL)
                micStarted = true
                logger.info("Microphone recording started")
            }

            try SystemAudioCapturePermission.ensureAuthorized()

            let systemURL = directory.appendingPathComponent("system.caf")
            try systemTap.start(writingTo: systemURL)
            logger.info("System audio tap started")

            let meta = SessionMetadata(
                systemStartHostTime: mach_absolute_time(),
                micStartHostTime: recordMicrophone ? micRecorder.startHostTime : nil,
                startedAt: Date()
            )
            let data = try JSONEncoder().encode(meta)
            try data.write(to: directory.appendingPathComponent("session.json"))
        } catch {
            logger.error("Recording start failed: \(error.localizedDescription, privacy: .public)")
            if micStarted {
                micRecorder.stop()
            }
            try? systemTap.stop()
            outputDirectory = nil
            throw error
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

    private func activateForCapture() {
        let activate = { NSApplication.shared.activate(ignoringOtherApps: true) }
        if Thread.isMainThread {
            activate()
        } else {
            DispatchQueue.main.sync(execute: activate)
        }
    }
}
