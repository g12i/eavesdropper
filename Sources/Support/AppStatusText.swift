import Foundation

enum TranscriptionPhase: Equatable {
    case idle
    case queued
    case running(detail: String)
    case succeeded
    case failed(message: String)
    case modelMissing
    case cancelled
    case skippedTooShort

    var isActive: Bool {
        switch self {
        case .queued, .running:
            true
        default:
            false
        }
    }
}

enum AppStatusText {
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
