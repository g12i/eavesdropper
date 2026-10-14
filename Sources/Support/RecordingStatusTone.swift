import SwiftUI

enum RecordingStatusTone: Equatable {
    case working
    case error
    case ready
    case noTranscript

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

enum GlobalStatusPresentation {
    static func tone(
        isRecording: Bool,
        transcription: TranscriptionPhase,
        modelReady: Bool,
        modelBusy: Bool
    ) -> RecordingStatusTone {
        if modelBusy {
            return .working
        }
        if isRecording {
            return .working
        }
        if case .running = transcription {
            return .working
        }
        if case .failed = transcription {
            return .error
        }
        if !modelReady {
            return .error
        }
        return .ready
    }

    static func label(
        isRecording: Bool,
        transcription: TranscriptionPhase,
        modelReady: Bool,
        modelBusy: Bool
    ) -> String {
        AppStatusText.compactGlobalStatus(
            isRecording: isRecording,
            transcription: transcription,
            modelReady: modelReady,
            modelBusy: modelBusy
        )
    }
}
