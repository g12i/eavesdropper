import AppKit
import Foundation

enum RecordingsLocation {
    static var rootDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    /// `~/Recordings/<yyyy-MM-dd_HH-mm-ss>/` for a session starting now.
    static func newSessionDirectory(now: Date = Date()) -> URL {
        rootDirectory.appendingPathComponent(sessionFolderFormatter.string(from: now), isDirectory: true)
    }

    static func ensureRootExists() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    static func revealSessionFolder(_ sessionDirectory: URL) {
        guard FileManager.default.fileExists(atPath: sessionDirectory.path) else {
            try? ensureRootExists()
            NSWorkspace.shared.open(rootDirectory)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([sessionDirectory])
    }

    private static let sessionFolderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()
}
