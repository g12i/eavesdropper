import AppKit

extension RecordingStatusTone {
    var nsColor: NSColor {
        switch self {
        case .working:
            .systemYellow
        case .error:
            .systemRed
        case .ready:
            .systemGreen
        case .noTranscript:
            .secondaryLabelColor
        case .configuration:
            .systemOrange
        }
    }
}
