import Foundation

enum SessionTranscriptionState: Equatable, Sendable {
    case idle(hasTranscript: Bool)
    case queued(language: TranscriptionLanguage)
    case loadingModel(language: TranscriptionLanguage)
    case transcribing(language: TranscriptionLanguage, fraction: Double)
    case cancelling
    case done(detectedLanguage: String?)
    case failed(message: String)

    var isActive: Bool {
        switch self {
        case .queued, .loadingModel, .transcribing, .cancelling:
            true
        default:
            false
        }
    }

    var hasTranscript: Bool {
        switch self {
        case .idle(let has):
            has
        case .done:
            true
        default:
            false
        }
    }
}

struct TranscriptionTask: Sendable {
    let sessionURL: URL
    let language: TranscriptionLanguage
}
