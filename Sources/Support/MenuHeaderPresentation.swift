import Foundation

enum ConfigurationRequirement: Equatable {
    case systemAudioPermission
    case whisperModel

    var menuTitle: String {
        switch self {
        case .systemAudioPermission:
            "Uprawnienia dźwięku systemu"
        case .whisperModel:
            "Pobierz model Whisper"
        }
    }
}

struct MenuHeaderModel: Equatable {
    let title: String
    let tone: RecordingStatusTone
    let missingRequirements: [ConfigurationRequirement]
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
            return MenuHeaderModel(title: elapsed, tone: .working, missingRequirements: [])
        }

        var missing: [ConfigurationRequirement] = []
        if systemAudioStatus == .denied {
            missing.append(.systemAudioPermission)
        }
        if !modelReady || modelBusy {
            missing.append(.whisperModel)
        }

        if missing.isEmpty {
            return MenuHeaderModel(title: "Gotowe", tone: .ready, missingRequirements: [])
        }
        return MenuHeaderModel(
            title: "Wymaga konfiguracji",
            tone: .configuration,
            missingRequirements: missing
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
