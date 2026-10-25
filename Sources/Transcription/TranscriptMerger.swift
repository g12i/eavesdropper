import Foundation

enum TranscriptMerger {
    private static let mergeGap: TimeInterval = 1.5
    private static let hallucinationPhrases = [
        "dziękuję za uwagę",
        "thank you for watching",
    ]

    static func merge(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        let cleaned = segments.map(sanitize)
        let filtered = cleaned.filter(shouldKeep).sorted { $0.start < $1.start }
        return coalesce(filtered)
    }

    static func writeTXT(_ segments: [TranscriptSegment], to url: URL) throws {
        let lines = segments.map { segment in
            "[\(formatClock(segment.start))] \(TranscriptTextSanitizer.clean(segment.text))"
        }
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeSRT(_ segments: [TranscriptSegment], to url: URL) throws {
        var blocks: [String] = []
        for (index, segment) in segments.enumerated() {
            let text = TranscriptTextSanitizer.clean(segment.text)
            blocks.append(
                """
                \(index + 1)
                \(formatSRT(segment.start)) --> \(formatSRT(segment.end))
                \(text)

                """
            )
        }
        try blocks.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func sanitize(_ segment: TranscriptSegment) -> TranscriptSegment {
        TranscriptSegment(
            start: segment.start,
            end: segment.end,
            text: TranscriptTextSanitizer.clean(segment.text),
            noSpeechProb: segment.noSpeechProb
        )
    }

    static func shouldKeep(_ segment: TranscriptSegment) -> Bool {
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if let prob = segment.noSpeechProb, prob > 0.6 { return false }
        let lower = trimmed.lowercased()
        for phrase in hallucinationPhrases where lower.contains(phrase) {
            return false
        }
        return true
    }

    static func coalesce(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard !segments.isEmpty else { return [] }
        var result: [TranscriptSegment] = []
        var current = segments[0]

        for segment in segments.dropFirst() {
            if segment.start - current.end <= mergeGap {
                current = TranscriptSegment(
                    start: current.start,
                    end: max(current.end, segment.end),
                    text: [current.text, segment.text].joined(separator: " "),
                    noSpeechProb: max(current.noSpeechProb ?? 0, segment.noSpeechProb ?? 0)
                )
            } else {
                result.append(current)
                current = segment
            }
        }
        result.append(current)
        return result
    }

    private static func formatClock(_ t: TimeInterval) -> String {
        let total = max(0, Int(t.rounded(.down)))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func formatSRT(_ t: TimeInterval) -> String {
        let clamped = max(0, t)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        let seconds = Int(clamped) % 60
        let millis = Int((clamped - floor(clamped)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }
}
