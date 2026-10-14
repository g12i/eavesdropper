import Foundation

enum RecordingSessionError: LocalizedError {
    case systemAudio(underlying: Error)
    case microphone(underlying: Error)

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
        case let .microphone(underlying):
            if let mic = underlying as? MicRecorderError {
                return mic.errorDescription
            }
            return "Mikrofon: \(underlying.localizedDescription)"
        }
    }

    var failurePhase: String {
        switch self {
        case .systemAudio: "system"
        case .microphone: "mic"
        }
    }
}
