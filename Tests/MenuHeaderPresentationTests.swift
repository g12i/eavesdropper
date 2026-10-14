import XCTest
@testable import TapScribe

final class MenuHeaderPresentationTests: XCTestCase {
    func testReadyWhenConfigured() {
        let model = MenuHeaderPresentation.model(
            isRecording: false,
            recordingElapsedMMSS: nil,
            systemAudioStatus: .unknown,
            modelReady: true,
            modelBusy: false
        )
        XCTAssertEqual(model.title, "Gotowe")
        XCTAssertEqual(model.tone, .ready)
        XCTAssertTrue(model.missingRequirements.isEmpty)
    }

    func testElapsedWhileRecording() {
        let model = MenuHeaderPresentation.model(
            isRecording: true,
            recordingElapsedMMSS: "01:05",
            systemAudioStatus: .denied,
            modelReady: false,
            modelBusy: true
        )
        XCTAssertEqual(model.title, "01:05")
        XCTAssertEqual(model.tone, .working)
        XCTAssertTrue(model.missingRequirements.isEmpty)
    }

    func testConfigurationMissingModelAndPermission() {
        let model = MenuHeaderPresentation.model(
            isRecording: false,
            recordingElapsedMMSS: nil,
            systemAudioStatus: .denied,
            modelReady: false,
            modelBusy: false
        )
        XCTAssertEqual(model.title, "Wymaga konfiguracji")
        XCTAssertEqual(model.tone, .configuration)
        XCTAssertEqual(model.missingRequirements, [.systemAudioPermission, .whisperModel])
    }

    func testRecordingElapsedFormat() {
        let start = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 125)
        XCTAssertEqual(RecordingElapsedFormat.mmss(since: start, now: now), "02:05")
    }
}
