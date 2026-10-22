import Foundation

enum ConfigurationRequirement: Equatable {
    case systemAudioPermission
    case whisperModel
    /// Download or first load in progress; the menu shows live status instead of "Download".
    case whisperModelPreparing

    /// Ellipsis per HIG: these open System Settings or the model window.
    var menuTitle: String {
        switch self {
        case .systemAudioPermission:
            "Enable system audio recording…"
        case .whisperModel:
            "Download transcription model (optional)…"
        case .whisperModelPreparing:
            "Downloading model…"
        }
    }

    /// Only capture blockers disable Start; Whisper is needed for transcription, not for recording.
    var blocksRecording: Bool {
        switch self {
        case .systemAudioPermission:
            true
        case .whisperModel, .whisperModelPreparing:
            false
        }
    }
}

struct MenuHeaderModel: Equatable {
    let title: String
    let tone: RecordingStatusTone
    let missingRequirements: [ConfigurationRequirement]
    let isRecording: Bool

    /// True when the menu shows **Wymaga konfiguracji** (including optional model setup).
    var needsSetup: Bool {
        !missingRequirements.isEmpty
    }

    /// True when Start nagrywania must stay disabled (e.g. system audio permission denied).
    var blocksRecording: Bool {
        missingRequirements.contains(where: \.blocksRecording)
    }

    /// Header row is hidden when configured and idle; shown for setup or elapsed time while recording.
    var shouldShowInMenu: Bool {
        isRecording || needsSetup
    }
}

enum MenuHeaderPresentation {
    static func model(
        isRecording: Bool,
        recordingElapsedMMSS: String?,
        systemAudioStatus: SystemAudioCapturePermission.Status,
        modelReady: Bool,
        modelBusy: Bool
    ) -> MenuHeaderModel {
        if isRecording {
            let elapsed = recordingElapsedMMSS ?? "00:00"
            return MenuHeaderModel(
                title: elapsed,
                tone: .working,
                missingRequirements: [],
                isRecording: true
            )
        }

        var missing: [ConfigurationRequirement] = []
        if systemAudioStatus == .denied {
            missing.append(.systemAudioPermission)
        }
        if modelBusy {
            missing.append(.whisperModelPreparing)
        } else if !modelReady {
            missing.append(.whisperModel)
        }

        if missing.isEmpty {
            return MenuHeaderModel(title: "", tone: .ready, missingRequirements: [], isRecording: false)
        }
        return MenuHeaderModel(
            title: "Setup required",
            tone: .configuration,
            missingRequirements: missing,
            isRecording: false
        )
    }
}

enum RecordingElapsedFormat {
    static func mmss(since start: Date, now: Date = Date()) -> String {
        mmss(totalSeconds: max(0, Int(now.timeIntervalSince(start))))
    }

    static func mmss(totalSeconds: Int) -> String {
        let clamped = max(0, totalSeconds)
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
