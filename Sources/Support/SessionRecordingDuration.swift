import AVFoundation
import Foundation

enum SessionRecordingDuration {
    static let minimumTranscriptionSeconds: TimeInterval = 60

    static func durationSeconds(in sessionDirectory: URL) -> TimeInterval? {
        let cafURL = sessionDirectory.appendingPathComponent("system.caf")
        guard FileManager.default.fileExists(atPath: cafURL.path) else {
            return nil
        }

        let asset = AVURLAsset(url: cafURL)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds >= 0 else {
            return nil
        }
        return seconds
    }

    static func isTooShortForTranscription(in sessionDirectory: URL) -> Bool {
        guard let seconds = durationSeconds(in: sessionDirectory) else {
            return false
        }
        return seconds < minimumTranscriptionSeconds
    }
}
