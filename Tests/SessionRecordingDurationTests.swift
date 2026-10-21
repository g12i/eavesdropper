import AVFoundation
import XCTest
@testable import Eavesdropper

final class SessionRecordingDurationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tapscribe-duration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeSilence(seconds: Double, sampleRate: Double = 48_000) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let file = try AVAudioFile(
            forWriting: directory.appendingPathComponent("system.caf"),
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
    }

    func testReadsDurationFromCAF() throws {
        try writeSilence(seconds: 2)
        let seconds = try XCTUnwrap(SessionRecordingDuration.durationSeconds(in: directory))
        XCTAssertEqual(seconds, 2, accuracy: 0.01)
    }

    func testReadsDurationShortRecording() throws {
        try writeSilence(seconds: 30)
        let seconds = try XCTUnwrap(SessionRecordingDuration.durationSeconds(in: directory))
        XCTAssertEqual(seconds, 30, accuracy: 0.01)
        XCTAssertTrue(SessionRecordingDuration.isTooShortForTranscription(in: directory))
    }

    func testMissingFileReturnsNil() {
        XCTAssertNil(SessionRecordingDuration.durationSeconds(in: directory))
        XCTAssertFalse(SessionRecordingDuration.isTooShortForTranscription(in: directory))
    }
}
