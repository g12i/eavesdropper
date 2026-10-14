import SwiftUI

enum RecordingStatusTone: Equatable {
    case working
    case error
    case ready
    case noTranscript
    case configuration

    var foregroundColor: Color {
        switch self {
        case .working:
            .yellow
        case .error:
            .red
        case .ready:
            .green
        case .noTranscript:
            .secondary
        case .configuration:
            .orange
        }
    }
}

extension RecordingSessionDisplayState {
    var statusTone: RecordingStatusTone {
        switch self {
        case .recording, .transcribing:
            .working
        case .error, .modelMissing:
            .error
        case .transcriptReady:
            .ready
        case .audioOnly, .tooShort:
            .noTranscript
        }
    }
}

extension RecordingMenuRow {
    var statusTone: RecordingStatusTone {
        displayState.statusTone
    }
}

