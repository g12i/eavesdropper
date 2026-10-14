import Foundation

enum TranscriptSpeaker: String, Codable, CaseIterable {
    case me = "Ja"
    case others = "Rozmówcy"
}

struct TranscriptSegment: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    let speaker: TranscriptSpeaker
    let noSpeechProb: Float?
}
