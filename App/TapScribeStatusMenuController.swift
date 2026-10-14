import AppKit

@MainActor
final class TapScribeStatusMenuController: NSObject, NSMenuDelegate {
    static let shared = TapScribeStatusMenuController()

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var menuIsOpen = false

    private override init() {
        super.init()
    }

    func install() {
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem?.menu = menu
        updateStatusIcon(isRecording: TapScribeApplicationController.shared.isRecording)
        rebuildMenu()
    }

    func updateStatusIcon(isRecording: Bool) {
        let symbol = isRecording ? "record.circle.fill" : "waveform"
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "TapScribe") else {
            return
        }
        image.isTemplate = !isRecording
        statusItem?.button?.image = image
    }

    func refreshIfNeeded() {
        let app = TapScribeApplicationController.shared
        updateStatusIcon(isRecording: app.isRecording)
        if menuIsOpen {
            rebuildMenu()
        }
    }

    func rebuildMenu() {
        let app = TapScribeApplicationController.shared
        menu.removeAllItems()

        let header = NSMenuItem()
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: app.globalStatusLabel,
            attributes: [
                .foregroundColor: app.globalStatusTone.nsColor,
                .font: NSFont.menuFont(ofSize: 12),
            ]
        )
        menu.addItem(header)
        menu.addItem(.separator())

        let rows = app.recordingMenuRows
        if rows.isEmpty {
            let empty = NSMenuItem(title: "Brak nagrań", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for row in rows {
                let item = NSMenuItem()
                item.representedObject = row.id
                item.target = self
                item.action = #selector(openRecording(_:))
                item.view = RecordingRowMenuView(row: row)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let toggleTitle = app.isRecording ? "Zakończ nagrywanie" : "Start nagrywania"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleRecording(_:)), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let finder = NSMenuItem(
            title: "Pokaż w Finderze",
            action: #selector(showInFinder(_:)),
            keyEquivalent: ""
        )
        finder.target = self
        menu.addItem(finder)

        let settings = NSMenuItem(title: "Ustawienia", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.autoenablesItems = true

        settingsMenu.addItem(withTitle: "Model transkrypcji…", action: #selector(openModelSettings(_:)), keyEquivalent: "")
        settingsMenu.addItem(withTitle: "Pobierz ponownie model…", action: #selector(redownloadModel(_:)), keyEquivalent: "")
        settingsMenu.addItem(.separator())
        settingsMenu.addItem(
            withTitle: "Dźwięk systemu (TCC)…",
            action: #selector(openSystemAudioSettings(_:)),
            keyEquivalent: ""
        )
        for item in settingsMenu.items where item.action != nil {
            item.target = self
        }
        menu.setSubmenu(settingsMenu, for: settings)

        let quit = NSMenuItem(title: "Zakończ", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        quit.target = self
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        let app = TapScribeApplicationController.shared
        app.refreshRecordingsList()
        rebuildMenu()
        Task { @MainActor in
            await app.whisperModelStore.refreshReadyState()
            rebuildMenu()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    @objc private func toggleRecording(_ sender: NSMenuItem) {
        Task { await TapScribeApplicationController.shared.toggleRecording() }
    }

    @objc private func openRecording(_ sender: NSMenuItem) {
        guard let sessionID = sender.representedObject as? String else { return }
        let app = TapScribeApplicationController.shared
        guard let row = app.recordingMenuRows.first(where: { $0.id == sessionID }) else { return }
        app.openRecording(row)
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        TapScribeApplicationController.shared.showInFinder()
    }

    @objc private func openModelSettings(_ sender: NSMenuItem) {
        TapScribeApplicationController.shared.presentOnboarding()
    }

    @objc private func redownloadModel(_ sender: NSMenuItem) {
        Task { await TapScribeApplicationController.shared.prepareRedownloadOnboarding() }
    }

    @objc private func openSystemAudioSettings(_ sender: NSMenuItem) {
        PrivacySettings.openSystemAudioRecording()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        TapScribeApplicationController.shared.quit()
    }
}
