import AppKit
import Foundation

enum RecordingsLocation {
    static var rootDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    static func ensureRootExists() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    static func displayPath(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func openInFinder(sessionDirectory: URL?) {
        do {
            try ensureRootExists()
        } catch {
            return
        }

        if let sessionDirectory, FileManager.default.fileExists(atPath: sessionDirectory.path) {
            let highlight = sessionDirectory.appendingPathComponent("system.caf")
            let urls: [URL]
            if FileManager.default.fileExists(atPath: highlight.path) {
                urls = [highlight]
            } else {
                urls = [sessionDirectory]
            }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            return
        }

        NSWorkspace.shared.open(rootDirectory)
    }

    static func revealSessionFolder(_ sessionDirectory: URL) {
        guard FileManager.default.fileExists(atPath: sessionDirectory.path) else {
            openInFinder(sessionDirectory: nil)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([sessionDirectory])
    }

    static func openRecordingsRootInFinder() {
        do {
            try ensureRootExists()
            NSWorkspace.shared.open(rootDirectory)
        } catch {
            // best effort
        }
    }
}
