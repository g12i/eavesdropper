import AppKit

final class RecordingRowMenuView: NSView {
    static let rowHeight: CGFloat = 24
    static let rowWidth: CGFloat = 300

    private let highlightView = NSView()
    private var isHighlighted = false

    init(row: RecordingMenuRow) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: Self.rowHeight))
        wantsLayer = true
        highlightView.wantsLayer = true
        addSubview(highlightView)
        build(row: row)
        updateTrackingAreas()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        highlightView.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        setHighlighted(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHighlighted(false)
    }

    private func setHighlighted(_ highlighted: Bool) {
        isHighlighted = highlighted
        highlightView.layer?.backgroundColor = highlighted
            ? NSColor.selectedContentBackgroundColor.cgColor
            : NSColor.clear.cgColor
    }

    private func build(row: RecordingMenuRow) {
        let iconView = NSImageView(frame: NSRect(x: 8, y: 4, width: 16, height: 16))
        if let symbol = row.systemImage ?? (row.displayState == .recording ? "record.circle.fill" : nil),
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iconView.image = image
            iconView.contentTintColor = row.displayState == .recording
                ? RecordingStatusTone.working.nsColor
                : .secondaryLabelColor
        }
        addSubview(iconView)

        let statusFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let statusWidth = ceil(
            (row.trailingStatus as NSString).size(withAttributes: [.font: statusFont]).width
        ) + 4
        let statusColumnWidth = min(max(statusWidth, 88), 120)

        let titleX: CGFloat = 28
        let titleWidth = Self.rowWidth - titleX - statusColumnWidth - 10

        let titleField = NSTextField(labelWithString: row.title)
        titleField.font = .menuFont(ofSize: 12)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.frame = NSRect(x: titleX, y: 3, width: max(titleWidth, 80), height: 18)
        addSubview(titleField)

        let statusField = NSTextField(labelWithString: row.trailingStatus)
        statusField.font = statusFont
        statusField.textColor = row.statusTone.nsColor
        statusField.alignment = .right
        statusField.frame = NSRect(
            x: Self.rowWidth - statusColumnWidth - 8,
            y: 3,
            width: statusColumnWidth,
            height: 18
        )
        addSubview(statusField)
    }
}
