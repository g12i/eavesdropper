import XCTest
@testable import TapScribe

final class RecordingMenuPresentationTests: XCTestCase {
    func testInlineMenuLineFormat() {
        let line = RecordingMenuPresentation.inlineMenuLine(title: "14.10 o 14:27", status: "Transkrypcja…")
        XCTAssertEqual(line, "14.10 o 14:27 · Transkrypcja…")
    }

    func testTranscriptReadyOmitsStatusText() {
        let url = URL(fileURLWithPath: "/tmp/session", isDirectory: true)
        let entry = RecordingSessionEntry(
            id: url.path,
            url: url,
            folderName: "session",
            startedAt: Date(),
            hasTranscript: true
        )
        let rows = RecordingMenuPresentation.rows(
            recent: [entry],
            activeRecordingDirectory: nil,
            isRecording: false,
            lastSessionPath: "/other",
            transcription: .idle,
            modelReady: true
        )
        XCTAssertEqual(rows.first?.displayState, .transcriptReady)
        XCTAssertEqual(rows.first?.trailingStatus, "")
        XCTAssertFalse(rows.first?.menuLineTitle.contains("·") ?? true)
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
        XCTAssertEqual(rows.first?.statusTone, .working)
    }

    func testReadyToneForTranscript() {
        let url = URL(fileURLWithPath: "/tmp/session", isDirectory: true)
        let entry = RecordingSessionEntry(
            id: url.path,
            url: url,
            folderName: "session",
            startedAt: Date(),
            hasTranscript: true
        )
        let rows = RecordingMenuPresentation.rows(
            recent: [entry],
            activeRecordingDirectory: nil,
            isRecording: false,
            lastSessionPath: "/other",
            transcription: .idle,
            modelReady: true
        )
        XCTAssertEqual(rows.first?.statusTone, .ready)
    }
}
