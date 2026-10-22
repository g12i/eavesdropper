import Foundation

enum TranscriptionPhase: Equatable {
    case idle
    case queued
    case running(detail: String)
    case succeeded
    case failed(message: String)
    case modelMissing
    case cancelled

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
    static func transcriptionDetail(from statusMessage: String) -> String {
        if statusMessage.contains("Download") {
            return "downloading model…"
        }
        if statusMessage.contains("Load") {
            return "loading model…"
        }
        if statusMessage.contains("Transcrib") {
            return "transcribing…"
        }
        if statusMessage.hasPrefix("Transcription:") {
            return String(statusMessage.dropFirst("Transcription:".count)).trimmingCharacters(in: .whitespaces)
        }
        return statusMessage
    }
}
