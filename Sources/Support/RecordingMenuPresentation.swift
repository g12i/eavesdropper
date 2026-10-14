import Foundation

enum RecordingSessionDisplayState: Equatable {
    case recording
    case audioOnly
    case queued
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
        case .queued:
            "hourglass"
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
        guard !status.isEmpty else { return trimmed }
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

    /// - Parameter transcriptionStates: phases from this app run, keyed by session folder path.
    ///   Sessions without an entry fall back to what is on disk.
    static func rows(
        recent: [RecordingSessionEntry],
        activeRecordingDirectory: URL?,
        isRecording: Bool,
        transcriptionStates: [String: TranscriptionPhase],
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
                transcription: transcriptionStates[entry.url.path],
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
        transcription: TranscriptionPhase?,
        modelReady: Bool
    ) -> RecordingSessionDisplayState {
        let isActiveRecording = isRecording && activeRecordingDirectory?.path == entry.url.path
        if isActiveRecording {
            return .recording
        }

        switch transcription {
        case .queued:
            return .queued
        case .running:
            return .transcribing
        case .modelMissing:
            return .modelMissing
        case .failed:
            return modelReady ? .error : .modelMissing
        case .succeeded:
            return entry.hasTranscript ? .transcriptReady : .error
        case .skippedTooShort:
            return .tooShort
        case .cancelled, .idle, nil:
            break
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
        case .queued:
            "W kolejce"
        case .transcribing:
            "Transkrypcja…"
        case .transcriptReady:
            ""
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

    private static let menuCompactDateFormatter: DateFormatter = {
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
