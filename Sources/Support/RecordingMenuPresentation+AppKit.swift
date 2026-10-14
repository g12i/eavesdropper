import AppKit

extension RecordingMenuPresentation {
    static func menuAttributedTitle(for row: RecordingMenuRow) -> NSAttributedString {
        let line = alignedTitle(title: row.title, status: row.trailingStatus)
        let titleFont = NSFont.menuFont(ofSize: 0)
        let statusFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let result = NSMutableAttributedString(
            string: line,
            attributes: [.font: titleFont, .foregroundColor: NSColor.labelColor]
        )
        let marker = "· \(row.trailingStatus)"
        if let swiftRange = line.range(of: marker, options: .backwards) {
            let nsRange = NSRange(swiftRange, in: line)
            result.addAttributes(
                [.foregroundColor: row.statusTone.nsColor, .font: statusFont],
                range: nsRange
            )
        }
        return result
    }

    static func menuSymbolImage(for row: RecordingMenuRow) -> NSImage? {
        let name = row.systemImage ?? (row.displayState == .recording ? "record.circle.fill" : "waveform")
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        image.isTemplate = row.displayState != .recording
        return image
    }
}
