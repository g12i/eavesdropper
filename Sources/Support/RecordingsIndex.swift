import Foundation

struct RecordingSessionEntry: Identifiable {
    let id: String
    let url: URL
    let folderName: String
    let startedAt: Date?
    let hasTranscript: Bool
}

enum RecordingsIndex {
    static func recent(limit: Int = 15) -> [RecordingSessionEntry] {
        let root = RecordingsLocation.rootDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }

        let entries: [RecordingSessionEntry] = names.compactMap { name in
            let url = root.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("system.caf").path) else {
                return nil
            }
            let startedAt = readStartedAt(from: url)
            let hasTranscript = FileManager.default.fileExists(
                atPath: url.appendingPathComponent("transcript.txt").path
            )
            return RecordingSessionEntry(
                id: url.path,
                url: url,
                folderName: name,
                startedAt: startedAt,
                hasTranscript: hasTranscript
            )
        }

        return entries.sorted { lhs, rhs in
            sortKey(for: lhs) > sortKey(for: rhs)
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func sortKey(for entry: RecordingSessionEntry) -> Double {
        if let startedAt = entry.startedAt {
            return startedAt.timeIntervalSince1970
        }
        let parsed = folderNameDateFormatter.date(from: entry.folderName)
        return parsed?.timeIntervalSince1970 ?? 0
    }

    private static let folderNameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    private static func readStartedAt(from sessionDirectory: URL) -> Date? {
        let metaURL = sessionDirectory.appendingPathComponent("session.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(SessionMetadata.self, from: data)
        else {
            return nil
        }
        return meta.startedAt
    }
}
