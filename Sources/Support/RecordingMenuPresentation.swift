import Foundation

enum RecordingSessionDisplayState: Equatable {
    case recording
    case audioOnly
    case transcribing
    case transcriptReady
    case error
    case modelMissing
    case tooShort
}

struct RecordingMenuRow: Identifiable {
    let id: String
    let url: URL
    let title: String
    let trailingStatus: String
    let displayState: RecordingSessionDisplayState

    var systemImage: String? {
        switch displayState {
        case .recording:
            nil
        case .audioOnly:
            "waveform"
        case .transcribing:
            "arrow.triangle.2.circlepath"
        case .transcriptReady:
            "checkmark.circle"
        case .error:
            "xmark.circle"
        case .modelMissing:
            "exclamationmark.triangle"
        case .tooShort:
            "clock"
        }
    }

    var menuLineTitle: String {
        RecordingMenuPresentation.inlineMenuLine(title: title, status: trailingStatus)
    }
}

enum RecordingMenuPresentation {
    static func inlineMenuLine(title: String, status: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return "\(trimmed) · \(status)"
    }

    static func polishTitle(for entry: RecordingSessionEntry) -> String {
        menuCompactTitle(for: entry.url, startedAt: entry.startedAt)
    }

    /// Shorter label so trailing status fits in the menu row.
    static func menuCompactTitle(for url: URL, startedAt: Date?) -> String {
        let date = startedAt
            ?? folderNameDateFormatter.date(from: url.lastPathComponent)
            ?? Date.distantPast
        if date == Date.distantPast {
            return url.lastPathComponent
        }
        return menuCompactDateFormatter.string(from: date)
    }

    static func polishTitle(for url: URL, startedAt: Date?) -> String {
        if let startedAt {
            return polishDateFormatter.string(from: startedAt)
        }
        if let parsed = folderNameDateFormatter.date(from: url.lastPathComponent) {
            return polishDateFormatter.string(from: parsed)
        }
        return url.lastPathComponent
    }

    static func rows(
        recent: [RecordingSessionEntry],
        activeRecordingDirectory: URL?,
        isRecording: Bool,
        lastSessionPath: String,
        transcription: TranscriptionPhase,
        modelReady: Bool
    ) -> [RecordingMenuRow] {
        var byPath: [String: RecordingSessionEntry] = [:]
        for entry in recent {
            byPath[entry.id] = entry
        }

        if isRecording, let active = activeRecordingDirectory {
            if byPath[active.path] == nil {
                let placeholder = RecordingSessionEntry(
                    id: active.path,
                    url: active,
                    folderName: active.lastPathComponent,
                    startedAt: nil,
                    hasTranscript: false
                )
                byPath[active.path] = placeholder
            }
        }

        let sorted = byPath.values.sorted { lhs, rhs in
            sortKey(lhs) > sortKey(rhs)
        }

        return sorted.prefix(15).map { entry in
            let state = displayState(
                for: entry,
                activeRecordingDirectory: activeRecordingDirectory,
                isRecording: isRecording,
                lastSessionPath: lastSessionPath,
                transcription: transcription,
                modelReady: modelReady
            )
            return RecordingMenuRow(
                id: entry.id,
                url: entry.url,
                title: polishTitle(for: entry),
                trailingStatus: trailingStatus(for: state),
                displayState: state
            )
        }
    }

    private static func displayState(
        for entry: RecordingSessionEntry,
        activeRecordingDirectory: URL?,
        isRecording: Bool,
        lastSessionPath: String,
        transcription: TranscriptionPhase,
        modelReady: Bool
    ) -> RecordingSessionDisplayState {
        let isActiveRecording = isRecording && activeRecordingDirectory?.path == entry.url.path
        if isActiveRecording {
            return .recording
        }

        let isLast = entry.url.path == lastSessionPath
        if isLast {
            switch transcription {
            case .running:
                return .transcribing
            case let .failed(message):
                if !modelReady || message.localizedCaseInsensitiveContains("model") {
                    return .modelMissing
                }
                return .error
            case .succeeded:
                return entry.hasTranscript ? .transcriptReady : .error
            case .skippedTooShort:
                return .tooShort
            case .cancelled, .idle:
                break
            }
        }

        if entry.hasTranscript {
            return .transcriptReady
        }
        if SessionRecordingDuration.isTooShortForTranscription(in: entry.url) {
            return .tooShort
        }
        return .audioOnly
    }

    private static func trailingStatus(for state: RecordingSessionDisplayState) -> String {
        switch state {
        case .recording:
            "Nagrywanie…"
        case .audioOnly:
            "Brak transkryptu"
        case .transcribing:
            "Transkrypcja…"
        case .transcriptReady:
            "Gotowe"
        case .error:
            "Błąd"
        case .modelMissing:
            "Brak modelu"
        case .tooShort:
            "Za krótkie"
        }
    }

    private static func sortKey(_ entry: RecordingSessionEntry) -> Double {
        if let startedAt = entry.startedAt {
            return startedAt.timeIntervalSince1970
        }
        return folderNameDateFormatter.date(from: entry.folderName)?.timeIntervalSince1970 ?? 0
    }

    private static let polishDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private     static let menuCompactDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "d.MM 'o' HH:mm"
        return f
    }()

    private static let folderNameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()
}

extension RecordingSessionEntry {
    var readablePolishDateTime: String {
        RecordingMenuPresentation.polishTitle(for: url, startedAt: startedAt)
    }
}
