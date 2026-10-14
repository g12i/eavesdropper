import XCTest
@testable import TapScribe

final class TranscriptMergerTests: XCTestCase {
    func testSortsByStartTime() {
        let mic = [seg(start: 5, end: 6, text: "B", speaker: .me)]
        let system = [seg(start: 1, end: 2, text: "A", speaker: .others)]
        let merged = TranscriptMerger.merge(micSegments: mic, systemSegments: system)
        XCTAssertEqual(merged.map(\.text), ["A", "B"])
    }

    func testMergesSameSpeakerWithinGap() {
        let mic = [
            seg(start: 0, end: 1, text: "Hej", speaker: .me),
            seg(start: 1.2, end: 2, text: "tam", speaker: .me),
        ]
        let merged = TranscriptMerger.merge(micSegments: mic, systemSegments: [])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "Hej tam")
    }

    func testSkipsEmptyAndNoSpeech() {
        let segments = [
            seg(start: 0, end: 1, text: "   ", speaker: .me),
            seg(start: 1, end: 2, text: "ok", speaker: .me, noSpeech: 0.9),
            seg(start: 2, end: 3, text: "Dziękuję za uwagę.", speaker: .others),
            seg(start: 3, end: 4, text: "tak", speaker: .me),
        ]
        let merged = TranscriptMerger.merge(micSegments: segments, systemSegments: [])
        XCTAssertEqual(merged.map(\.text), ["tak"])
    }

    func testSRTFormat() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tapscribe-srt-test.srt")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let segments = [seg(start: 1.5, end: 3.25, text: "Cześć", speaker: .me)]
        try TranscriptMerger.writeSRT(segments, to: tmp)
        let content = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(content.contains("00:00:01,500 --> 00:00:03,250"))
        XCTAssertTrue(content.contains("Ja: Cześć"))
    }

    private func seg(
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        speaker: TranscriptSpeaker,
        noSpeech: Float? = nil
    ) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text, speaker: speaker, noSpeechProb: noSpeech)
    }
}
