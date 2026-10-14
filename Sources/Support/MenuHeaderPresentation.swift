import Foundation

enum ConfigurationRequirement: Equatable {
    case systemAudioPermission
    case whisperModel
    /// Download or first load in progress; the menu shows live status instead of "Pobierz".
    case whisperModelPreparing

    var menuTitle: String {
        switch self {
        case .systemAudioPermission:
            "Uprawnienia dźwięku systemu"
        case .whisperModel:
            "Pobierz model Whisper"
        case .whisperModelPreparing:
            "Przygotowywanie modelu…"
        }
    }
}

struct MenuHeaderModel: Equatable {
    let title: String
    let tone: RecordingStatusTone
    let missingRequirements: [ConfigurationRequirement]
    let isRecording: Bool

    /// True when the menu shows **Wymaga konfiguracji** (Start nagrywania must stay disabled).
    var needsSetup: Bool {
        !missingRequirements.isEmpty
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
            title: "Wymaga konfiguracji",
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
