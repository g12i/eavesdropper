import AppKit

@MainActor
final class TapScribeStatusMenuController: NSObject, NSMenuDelegate {
    static let shared = TapScribeStatusMenuController()

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var menuIsOpen = false
    private var pendingMenuRebuild = false

    private static let statusSymbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)

    private override init() {
        super.init()
    }

    func install() {
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        menu.autoenablesItems = false
        if let button = statusItem?.button {
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.appearsDisabled = false
        }
        statusItem?.menu = menu
        updateStatusBar(
            isRecording: TapScribeApplicationController.shared.isRecording,
            elapsedMMSS: TapScribeApplicationController.shared.recordingElapsedMMSS
        )
        rebuildMenu()
    }

    func updateStatusBar(isRecording: Bool, elapsedMMSS: String?) {
        guard let button = statusItem?.button else { return }

        let symbol = isRecording ? "record.circle" : "waveform.circle"
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "TapScribe")
        let image = base?.withSymbolConfiguration(Self.statusSymbolConfiguration) ?? base
        guard let image else { return }

        image.isTemplate = true
        button.imagePosition = .imageLeading
        button.appearsDisabled = false
        button.image = image

        if isRecording {
            button.contentTintColor = .systemRed
            if let elapsedMMSS {
                button.title = " \(elapsedMMSS)"
            } else {
                button.title = " 00:00"
            }
        } else {
            button.contentTintColor = nil
            button.title = ""
        }
    }

    /// Rebuilds the dropdown unless it is on-screen (AppKit crashes on `removeAllItems` while tracking).
    func scheduleMenuRebuild() {
        guard !menuIsOpen else {
            pendingMenuRebuild = true
            return
        }
        rebuildMenu()
    }

    func refreshIfNeeded() {
        let app = TapScribeApplicationController.shared
        updateStatusBar(isRecording: app.isRecording, elapsedMMSS: app.recordingElapsedMMSS)
        scheduleMenuRebuild()
    }

    func rebuildMenu() {
        let app = TapScribeApplicationController.shared
        menu.removeAllItems()

        addMenuHeader(for: app)
        menu.addItem(.separator())

        let toggleTitle = app.isRecording ? "Zakończ nagrywanie" : "Start nagrywania"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleRecording(_:)), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        let rows = app.recordingMenuRows
        if rows.isEmpty {
            let empty = NSMenuItem(title: "Brak nagrań", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for row in rows {
                let item = NSMenuItem()
                item.representedObject = row.url
                item.target = self
                item.action = #selector(revealInFinder(_:))
                item.isEnabled = true
                item.attributedTitle = RecordingMenuPresentation.menuAttributedTitle(for: row)
                item.image = RecordingMenuPresentation.menuSymbolImage(for: row)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

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

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menuIsOpen = true
            pendingMenuRebuild = false
            let app = TapScribeApplicationController.shared
            app.refreshRecordingsList()
            rebuildMenu()
            Task { @MainActor in
                await app.whisperModelStore.refreshReadyState()
                rebuildMenu()
            }
        }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menuIsOpen = false
            if pendingMenuRebuild {
                pendingMenuRebuild = false
                rebuildMenu()
            }
        }
    }

    private func addMenuHeader(for app: TapScribeApplicationController) {
        let model = app.menuHeader
        let header = NSMenuItem()
        header.attributedTitle = NSAttributedString(
            string: model.title,
            attributes: [
                .foregroundColor: model.tone.nsColor,
                .font: NSFont.menuFont(ofSize: 12),
            ]
        )

        if model.missingRequirements.isEmpty {
            header.isEnabled = false
            menu.addItem(header)
            return
        }

        let configMenu = NSMenu()
        for requirement in model.missingRequirements {
            let item = NSMenuItem(title: requirement.menuTitle, action: nil, keyEquivalent: "")
            switch requirement {
            case .systemAudioPermission:
                item.action = #selector(openSystemAudioSettings(_:))
            case .whisperModel:
                item.action = #selector(openModelSettings(_:))
            }
            item.target = self
            configMenu.addItem(item)
        }
        menu.setSubmenu(configMenu, for: header)
        menu.addItem(header)
    }

    @objc private func toggleRecording(_ sender: NSMenuItem) {
        Task { @MainActor in
            await TapScribeApplicationController.shared.toggleRecording()
        }
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let folderURL = sender.representedObject as? URL else { return }
        TapScribeApplicationController.shared.openRecordingFolder(folderURL)
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
