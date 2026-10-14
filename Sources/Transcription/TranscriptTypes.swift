import Foundation

struct TranscriptSegment: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    let noSpeechProb: Float?
}
