import AVFoundation
import Foundation

enum SessionRecordingDuration {
    static let minimumTranscriptionSeconds: TimeInterval = 60

    private struct CacheKey: Hashable {
        let path: String
        let size: Int
    }

    private static let cacheLock = NSLock()
    private static var cache: [CacheKey: TimeInterval] = [:]

    /// Reads the CAF header via `AVAudioFile` (cheap, synchronous) and caches by path + size,
    /// because the menu asks for every listed session on each open.
    static func durationSeconds(in sessionDirectory: URL) -> TimeInterval? {
        let cafURL = sessionDirectory.appendingPathComponent("system.caf")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cafURL.path),
              let size = (attributes[.size] as? NSNumber)?.intValue
        else {
            return nil
        }

        let key = CacheKey(path: cafURL.path, size: size)
        cacheLock.lock()
        let cached = cache[key]
        cacheLock.unlock()
        if let cached {
            return cached
        }

        guard let file = try? AVAudioFile(forReading: cafURL) else {
            return nil
        }
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0 else {
            return nil
        }
        let seconds = Double(file.length) / sampleRate
        guard seconds.isFinite, seconds >= 0 else {
            return nil
        }

        cacheLock.lock()
        cache[key] = seconds
        cacheLock.unlock()
        return seconds
    }

    static func isTooShortForTranscription(in sessionDirectory: URL) -> Bool {
        guard let seconds = durationSeconds(in: sessionDirectory) else {
            return false
        }
        return seconds < minimumTranscriptionSeconds
    }
}
