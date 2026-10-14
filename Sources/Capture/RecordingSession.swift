import Foundation

struct SessionMetadata: Codable {
    let systemStartHostTime: UInt64?
    let micStartHostTime: UInt64?
    let startedAt: Date
}

final class RecordingSession {
    private let systemTap = SystemAudioTap()
    private let micRecorder = MicRecorder()
    private(set) var outputDirectory: URL?

    var isRecording: Bool { systemTap.isRunning }

    func start(in directory: URL, recordMicrophone: Bool) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        outputDirectory = directory

        let systemURL = directory.appendingPathComponent("system.caf")
        try systemTap.start(writingTo: systemURL)

        if recordMicrophone {
            let micURL = directory.appendingPathComponent("mic.caf")
            try micRecorder.start(writingTo: micURL)
        }

        let meta = SessionMetadata(
            systemStartHostTime: mach_absolute_time(),
            micStartHostTime: recordMicrophone ? micRecorder.startHostTime : nil,
            startedAt: Date()
        )
        let data = try JSONEncoder().encode(meta)
        try data.write(to: directory.appendingPathComponent("session.json"))
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
}
