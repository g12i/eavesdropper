import Foundation

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case polish = "pl"
    case english = "en"
    case auto = "auto"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .polish:
            "Polski"
        case .english:
            "Angielski"
        case .auto:
            "Auto"
        }
    }

    static var stored: TranscriptionLanguage {
        stored(in: .standard)
    }

    static func stored(in defaults: UserDefaults) -> TranscriptionLanguage {
        guard let raw = defaults.string(forKey: "transcriptionLanguage"),
              let language = TranscriptionLanguage(rawValue: raw) else {
            return .polish
        }
        return language
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "transcriptionLanguage")
    }
}
