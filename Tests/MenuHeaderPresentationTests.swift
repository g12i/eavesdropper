import XCTest
@testable import Eavesdropper

final class MenuHeaderPresentationTests: XCTestCase {
    func testReadyWhenConfigured() {
        let model = MenuHeaderPresentation.model(
            isRecording: false,
            recordingElapsedMMSS: nil,
            systemAudioStatus: .unknown,
            modelReady: true,
            modelBusy: false
        )
        XCTAssertTrue(model.missingRequirements.isEmpty)
        XCTAssertFalse(model.shouldShowInMenu)
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
        XCTAssertTrue(model.shouldShowInMenu)
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
        XCTAssertTrue(model.needsSetup)
    }

    func testDownloadInProgressShowsPreparingInsteadOfDownloadAction() {
        let model = MenuHeaderPresentation.model(
            isRecording: false,
            recordingElapsedMMSS: nil,
            systemAudioStatus: .authorized,
            modelReady: true,
            modelBusy: true
        )
        XCTAssertEqual(model.missingRequirements, [.whisperModelPreparing])
        XCTAssertTrue(model.needsSetup)
    }

    func testMissingModelDoesNotBlockRecording() {
        let model = MenuHeaderPresentation.model(
            isRecording: false,
            recordingElapsedMMSS: nil,
            systemAudioStatus: .authorized,
            modelReady: false,
            modelBusy: false
        )
        XCTAssertEqual(model.missingRequirements, [.whisperModel])
        XCTAssertTrue(model.needsSetup)
        XCTAssertFalse(model.blocksRecording)
    }

    func testDownloadInProgressDoesNotBlockRecording() {
        let model = MenuHeaderPresentation.model(
            isRecording: false,
            recordingElapsedMMSS: nil,
            systemAudioStatus: .unknown,
            modelReady: false,
            modelBusy: true
        )
        XCTAssertFalse(model.blocksRecording)
    }

    func testDeniedPermissionBlocksRecording() {
        let model = MenuHeaderPresentation.model(
            isRecording: false,
            recordingElapsedMMSS: nil,
            systemAudioStatus: .denied,
            modelReady: true,
            modelBusy: false
        )
        XCTAssertEqual(model.missingRequirements, [.systemAudioPermission])
        XCTAssertTrue(model.blocksRecording)
    }

    func testNeedsSetupFalseWhenGotowe() {
        let model = MenuHeaderPresentation.model(
            isRecording: false,
            recordingElapsedMMSS: nil,
            systemAudioStatus: .authorized,
            modelReady: true,
            modelBusy: false
        )
        XCTAssertFalse(model.needsSetup)
    }

    func testRecordingElapsedFormat() {
        let start = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 125)
        XCTAssertEqual(RecordingElapsedFormat.mmss(since: start, now: now), "02:05")
    }
}
