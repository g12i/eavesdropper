import Foundation

enum RecordingSessionError: LocalizedError {
    case systemAudio(underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .systemAudio(underlying):
            if let sys = underlying as? SystemAudioCaptureError {
                return sys.errorDescription
            }
            if let core = underlying as? CoreAudioError {
                return "Dźwięk systemu: \(core.errorDescription ?? underlying.localizedDescription)"
            }
            return "Dźwięk systemu: \(underlying.localizedDescription)"
        }
    }
}
