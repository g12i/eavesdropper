import XCTest
@testable import Eavesdropper

final class RecordingMenuPresentationTests: XCTestCase {
    func testInlineMenuLineFormat() {
        let line = RecordingMenuPresentation.inlineMenuLine(title: "Oct 14, 2:27 PM", status: "Transcribing…")
        XCTAssertEqual(line, "Oct 14, 2:27 PM · Transcribing…")
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
            transcriptionStates: [:],
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
            transcriptionStates: [url.path: .running(detail: "test")],
            modelReady: true
        )
        XCTAssertEqual(rows.first?.displayState, .transcribing)
        XCTAssertEqual(rows.first?.trailingStatus, "Transcribing…")
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
            transcriptionStates: [:],
            modelReady: true
        )
        XCTAssertEqual(rows.first?.statusTone, .ready)
    }

    func testTranscriptionStateIsPerSession() {
        let older = URL(fileURLWithPath: "/tmp/2025-10-14_13-00-00", isDirectory: true)
        let newer = URL(fileURLWithPath: "/tmp/2025-10-14_14-00-00", isDirectory: true)
        let entries = [older, newer].map { url in
            RecordingSessionEntry(
                id: url.path,
                url: url,
                folderName: url.lastPathComponent,
                startedAt: nil,
                hasTranscript: false
            )
        }
        let rows = RecordingMenuPresentation.rows(
            recent: entries,
            activeRecordingDirectory: newer,
            isRecording: true,
            transcriptionStates: [older.path: .running(detail: "")],
            modelReady: true
        )
        XCTAssertEqual(rows.map(\.displayState), [.recording, .transcribing])
    }

    func testQueuedSessionShowsQueueStatus() {
        let url = URL(fileURLWithPath: "/tmp/2025-10-14_13-00-00", isDirectory: true)
        let entry = RecordingSessionEntry(
            id: url.path,
            url: url,
            folderName: url.lastPathComponent,
            startedAt: nil,
            hasTranscript: false
        )
        let rows = RecordingMenuPresentation.rows(
            recent: [entry],
            activeRecordingDirectory: nil,
            isRecording: false,
            transcriptionStates: [url.path: .queued],
            modelReady: true
        )
        XCTAssertEqual(rows.first?.displayState, .queued)
        XCTAssertEqual(rows.first?.trailingStatus, "Queued")
        XCTAssertEqual(rows.first?.statusTone, .working)
    }
}
