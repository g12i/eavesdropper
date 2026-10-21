import Foundation

enum TranscriptionPolicy {
    static let shortRecordingThreshold: TimeInterval = 60

    static func isShort(duration: TimeInterval) -> Bool {
        duration < shortRecordingThreshold
    }
}
