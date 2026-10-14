import Foundation

enum TranscriptionPhase: Equatable {
    case idle
    case running(detail: String)
    case succeeded
    case failed(message: String)
    case cancelled
}

enum AppStatusText {
    static func compactGlobalStatus(
        isRecording: Bool,
        transcription: TranscriptionPhase,
        modelReady: Bool,
        modelBusy: Bool
    ) -> String {
        let activity: String
        if isRecording {
            activity = "Nagrywanie"
        } else {
            switch transcription {
            case .idle, .cancelled, .succeeded:
                activity = "Gotowy"
            case .running:
                activity = "Transkrypcja"
            case .failed:
                activity = "Błąd"
            }
        }

        let whisper: String
        if modelReady {
            whisper = "Whisper OK"
        } else if modelBusy {
            whisper = "Whisper…"
        } else {
            whisper = "Whisper brak"
        }

        return "\(activity) · \(whisper)"
    }

    static func mainLine(isRecording: Bool, transcription: TranscriptionPhase) -> String {
        if isRecording {
            return "Status: nagrywanie…"
        }
        switch transcription {
        case .idle:
            return "Status: gotowy"
        case let .running(detail):
            if detail.isEmpty {
                return "Status: transkrypcja…"
            }
            return "Status: transkrypcja… (\(detail))"
        case .succeeded:
            return "Status: gotowe"
        case let .failed(message):
            return "Status: błąd — \(message)"
        case .cancelled:
            return "Status: gotowy (transkrypcja anulowana)"
        }
    }

    static func transcriptLine(for sessionDirectory: URL?, transcription: TranscriptionPhase) -> String {
        guard let sessionDirectory else {
            return "Transkrypt: brak ostatniej sesji"
        }
        let transcriptPath = sessionDirectory.appendingPathComponent("transcript.txt")
        switch transcription {
        case .running:
            return "Transkrypt: w toku…"
        case .succeeded:
            return FileManager.default.fileExists(atPath: transcriptPath.path)
                ? "Transkrypt: gotowy (transcript.txt)"
                : "Transkrypt: brak pliku"
        case .failed, .cancelled:
            return FileManager.default.fileExists(atPath: transcriptPath.path)
                ? "Transkrypt: gotowy (transcript.txt)"
                : "Transkrypt: brak (nagranie zapisane)"
        case .idle:
            return FileManager.default.fileExists(atPath: transcriptPath.path)
                ? "Transkrypt: jest"
                : "Transkrypt: brak"
        }
    }

    static func polishTranscriptionDetail(from statusMessage: String) -> String {
        if statusMessage.contains("pobieranie modelu") {
            return "pobieranie modelu…"
        }
        if statusMessage.contains("ładowanie modelu") {
            return "ładowanie modelu…"
        }
        if statusMessage.contains("rozpoznawanie") || statusMessage.contains("dźwięk systemu") {
            return "rozpoznawanie mowy…"
        }
        if statusMessage.hasPrefix("Transkrypcja:") {
            return String(statusMessage.dropFirst("Transkrypcja:".count)).trimmingCharacters(in: .whitespaces)
        }
        return statusMessage
    }
}
