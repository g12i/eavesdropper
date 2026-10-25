import XCTest
@testable import Eavesdropper

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

    func testStripsWhisperSpecialTokens() {
        let segments = [
            seg(
                start: 0,
                end: 2,
                text: "<|startoftranscript|><|pl|><|transcribe|>Wykład medyczny"
            ),
            seg(start: 2, end: 4, text: "<|2.00|> kontynuacja"),
            seg(start: 4, end: 5, text: "<|endoftext|>"),
        ]
        let merged = TranscriptMerger.merge(segments)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "Wykład medyczny kontynuacja")
    }

    func testTXTAndSRTOmitSpecialTokens() throws {
        let segments = [
            seg(start: 0, end: 1, text: "<|startoftranscript|><|pl|>Cześć"),
        ]
        let txt = FileManager.default.temporaryDirectory.appendingPathComponent("tapscribe-txt-test.txt")
        let srt = FileManager.default.temporaryDirectory.appendingPathComponent("tapscribe-txt-test.srt")
        defer {
            try? FileManager.default.removeItem(at: txt)
            try? FileManager.default.removeItem(at: srt)
        }
        try TranscriptMerger.writeTXT(segments, to: txt)
        try TranscriptMerger.writeSRT(segments, to: srt)
        let txtContent = try String(contentsOf: txt, encoding: .utf8)
        let srtContent = try String(contentsOf: srt, encoding: .utf8)
        XCTAssertTrue(txtContent.contains("Cześć"))
        XCTAssertFalse(txtContent.contains("<|"))
        XCTAssertTrue(srtContent.contains("Cześć"))
        XCTAssertFalse(srtContent.contains("<|"))
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
