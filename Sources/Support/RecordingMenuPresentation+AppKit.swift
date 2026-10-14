import AppKit

extension RecordingMenuPresentation {
    static func menuAttributedTitle(for row: RecordingMenuRow) -> NSAttributedString {
        let line = inlineMenuLine(title: row.title, status: row.trailingStatus)
        let font = NSFont.menuFont(ofSize: 0)
        let result = NSMutableAttributedString(
            string: line,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        let marker = " · \(row.trailingStatus)"
        if let swiftRange = line.range(of: marker, options: .backwards) {
            let nsRange = NSRange(swiftRange, in: line)
            result.addAttributes(
                [.foregroundColor: row.statusTone.nsColor, .font: font],
                range: nsRange
            )
        }
        return result
    }

    static func menuSymbolImage(for row: RecordingMenuRow) -> NSImage? {
        let name = row.systemImage ?? (row.displayState == .recording ? "record.circle" : "waveform")
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}
