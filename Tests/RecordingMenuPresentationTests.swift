import XCTest
@testable import TapScribe

final class RecordingMenuPresentationTests: XCTestCase {
    func testAlignedTitlePadsStatusColumn() {
        let line = RecordingMenuPresentation.alignedTitle(title: "14 paź 2025, 13:20", status: "Gotowe")
        XCTAssertTrue(line.contains("· Gotowe"))
        XCTAssertTrue(line.hasPrefix("14 paź 2025, 13:20"))
    }

    func testTranscribingStateForLastSession() {
        let url = URL(fileURLWithPath: "/tmp/2025-10-14_13-00-00", isDirectory: true)
        let entry = RecordingSessionEntry(
            id: url.path,
            url: url,
            folderName: url.lastPathComponent,
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            hasTranscript: false
        )
        let rows = RecordingMenuPresentation.rows(
            recent: [entry],
            activeRecordingDirectory: nil,
            isRecording: false,
            lastSessionPath: url.path,
            transcription: .running(detail: "test"),
            modelReady: true
        )
        XCTAssertEqual(rows.first?.displayState, .transcribing)
        XCTAssertEqual(rows.first?.trailingStatus, "Transkrypcja…")
    }
}
