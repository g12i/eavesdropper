import XCTest
@testable import TapScribe

final class TranscriptMergerTests: XCTestCase {
    func testSortsByStartTime() {
        let segments = [
            seg(start: 5, end: 6, text: "B"),
            seg(start: 1, end: 2, text: "A"),
        ]
        let merged = TranscriptMerger.merge(segments)
        XCTAssertEqual(merged.map(\.text), ["A", "B"])
    }

    func testMergesAdjacentWithinGap() {
        let segments = [
            seg(start: 0, end: 1, text: "Hej"),
            seg(start: 1.2, end: 2, text: "tam"),
        ]
        let merged = TranscriptMerger.merge(segments)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "Hej tam")
    }

    func testSkipsEmptyAndNoSpeech() {
        let segments = [
            seg(start: 0, end: 1, text: "   "),
            seg(start: 1, end: 2, text: "ok", noSpeech: 0.9),
            seg(start: 2, end: 3, text: "Dziękuję za uwagę."),
            seg(start: 3, end: 4, text: "tak"),
        ]
        let merged = TranscriptMerger.merge(segments)
        XCTAssertEqual(merged.map(\.text), ["tak"])
    }

    func testSRTFormat() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tapscribe-srt-test.srt")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let segments = [seg(start: 1.5, end: 3.25, text: "Cześć")]
        try TranscriptMerger.writeSRT(segments, to: tmp)
        let content = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(content.contains("00:00:01,500 --> 00:00:03,250"))
        XCTAssertTrue(content.contains("Cześć"))
        XCTAssertFalse(content.contains("Ja:"))
    }

    private func seg(
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        noSpeech: Float? = nil
    ) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text, noSpeechProb: noSpeech)
    }
}
