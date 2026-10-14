import AppKit

final class RecordingRowMenuView: NSView {
    static let rowHeight: CGFloat = 22
    static let rowWidth: CGFloat = 260

    init(row: RecordingMenuRow) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: Self.rowHeight))
        build(row: row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(row: RecordingMenuRow) {
        let iconView = NSImageView(frame: NSRect(x: 8, y: 3, width: 16, height: 16))
        if let symbol = row.systemImage ?? (row.displayState == .recording ? "record.circle.fill" : nil),
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iconView.image = image
            iconView.contentTintColor = row.displayState == .recording
                ? RecordingStatusTone.working.nsColor
                : .secondaryLabelColor
        }
        addSubview(iconView)

        let statusWidth: CGFloat = 96
        let titleX: CGFloat = 28
        let titleWidth = Self.rowWidth - titleX - statusWidth - 8

        let titleField = NSTextField(labelWithString: row.title)
        titleField.font = .menuFont(ofSize: 13)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.frame = NSRect(x: titleX, y: 2, width: titleWidth, height: 18)
        addSubview(titleField)

        let statusField = NSTextField(labelWithString: row.trailingStatus)
        statusField.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        statusField.textColor = row.statusTone.nsColor
        statusField.alignment = .right
        statusField.frame = NSRect(x: Self.rowWidth - statusWidth - 6, y: 2, width: statusWidth, height: 18)
        addSubview(statusField)
    }
}
