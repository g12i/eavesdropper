import Foundation

enum RecordingStatusTone: Equatable {
    case working
    case error
    case ready
    case noTranscript
    case configuration
}

extension RecordingSessionDisplayState {
    var statusTone: RecordingStatusTone {
        switch self {
        case .recording, .queued, .transcribing:
            .working
        case .error, .modelMissing:
            .error
        case .transcriptReady:
            .ready
        case .audioOnly:
            .noTranscript
        }
    }
}

extension RecordingMenuRow {
    var statusTone: RecordingStatusTone {
        displayState.statusTone
    }
}
