import AppKit
import ServiceManagement

@MainActor
final class EavesdropperStatusMenuController: NSObject, NSMenuDelegate {
    static let shared = EavesdropperStatusMenuController()

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var menuIsOpen = false
    private var displayedRecordingState: Bool?

    /// Items kept so the open menu can be updated in place (elapsed time, row status) without rebuilding.
    private var headerItem: NSMenuItem?
    private var headerIsRecording = false
    private var toggleItem: NSMenuItem?
    private var rowItems: [NSMenuItem] = []
    private var rowIDs: [String] = []

    private static let statusSymbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)

    private override init() {
        super.init()
    }

    func install() {
        guard statusItem == nil else { return }

        // Image-only, same-size symbols in both states: a status item that grows (e.g. an MM:SS title) is
        // silently hidden by macOS when it no longer fits beside the notch.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.title = ""
        }
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item

        updateStatusButton()
        rebuildMenu()
    }

    /// Cheap enough to call every second: updates the icon only on state change and patches the open menu in place.
    /// A closed menu is rebuilt lazily in `menuNeedsUpdate`.
    func refresh() {
        updateStatusButton()
        if menuIsOpen {
            updateOpenMenuInPlace()
        }
    }

    private func updateStatusButton() {
        guard let statusItem, let button = statusItem.button else { return }
        if !statusItem.isVisible {
            statusItem.isVisible = true
        }

        let isRecording = EavesdropperApplicationController.shared.isRecording
        guard displayedRecordingState != isRecording else { return }
        displayedRecordingState = isRecording

        button.image = Self.statusBarImage(isRecording: isRecording)
        button.toolTip = isRecording ? "Eavesdropper - Recording" : "Eavesdropper"
    }

    private static func statusBarImage(isRecording: Bool) -> NSImage? {
        if isRecording {
            let palette = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
                .applying(statusSymbolConfiguration)
            let base = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Eavesdropper - Recording")
            return base?.withSymbolConfiguration(palette) ?? base
        }

        guard let base = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Eavesdropper") else {
            return nil
        }
        let image = base.withSymbolConfiguration(statusSymbolConfiguration) ?? base
        image.isTemplate = true
        return image
    }

    // MARK: - Menu construction

    private func rebuildMenu() {
        let app = EavesdropperApplicationController.shared
        menu.removeAllItems()
        headerItem = nil
        toggleItem = nil
        rowItems = []
        rowIDs = []

        let headerModel = app.menuHeader
        if headerModel.shouldShowInMenu {
            addMenuHeader(model: headerModel)
            menu.addItem(.separator())
        }

        let toggle = NSMenuItem(title: "", action: #selector(toggleRecording(_:)), keyEquivalent: "")
        toggle.target = self
        configureToggle(toggle, header: headerModel)
        menu.addItem(toggle)
        toggleItem = toggle

        menu.addItem(.separator())

        let rows = app.recordingMenuRows
        if rows.isEmpty {
            let empty = NSMenuItem(title: "No recordings", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for row in rows {
                let item = NSMenuItem(title: "", action: #selector(openTranscriptionDialog(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = row.url
                item.isEnabled = !row.isRecording
                configureRow(item, row: row)
                menu.addItem(item)
                rowItems.append(item)

                let altItem = NSMenuItem(title: "Show in Finder", action: #selector(revealInFinder(_:)), keyEquivalent: "")
                altItem.target = self
                altItem.representedObject = row.url
                altItem.isAlternate = true
                altItem.keyEquivalentModifierMask = .option
                menu.addItem(altItem)
            }
            rowIDs = rows.map(\.id)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.autoenablesItems = false
        addItem(to: settingsMenu, title: "Open Recordings Folder", action: #selector(openRecordingsFolder(_:)))
        let launchAtLogin = addItem(to: settingsMenu, title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)))
        switch LaunchAtLogin.state {
        case .enabled:
            launchAtLogin.state = .on
        case .requiresApproval:
            launchAtLogin.state = .mixed
            launchAtLogin.toolTip = "Requires approval in System Settings - General - Login Items."
        case .disabled:
            launchAtLogin.state = .off
        }
        let store = app.whisperModelStore
        if store.isReady, !store.isBusy {
            let advanced = NSMenuItem(title: "Advanced", action: nil, keyEquivalent: "")
            let advancedMenu = NSMenu()
            advancedMenu.autoenablesItems = false
            let redownload = addItem(to: advancedMenu, title: "Re-download Model…", action: #selector(redownloadModel(_:)))
            advanced.submenu = advancedMenu
            settingsMenu.addItem(.separator())
            settingsMenu.addItem(advanced)
        }
        settings.submenu = settingsMenu
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        quit.target = self
        menu.addItem(quit)
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func configureToggle(_ item: NSMenuItem, header: MenuHeaderModel) {
        let app = EavesdropperApplicationController.shared
        item.title = app.isRecording ? "Stop Recording" : "Start Recording"
        item.isEnabled = !app.isTogglingRecording && (app.isRecording || !header.blocksRecording)
    }

    private func configureRow(_ item: NSMenuItem, row: RecordingMenuRow) {
        item.attributedTitle = RecordingMenuPresentation.menuAttributedTitle(for: row)
        item.image = RecordingMenuPresentation.menuSymbolImage(for: row)
    }

    private func addMenuHeader(model: MenuHeaderModel) {
        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.attributedTitle = Self.headerTitle(model)
        headerItem = header
        headerIsRecording = model.isRecording

        if model.isRecording {
            header.isEnabled = false
            menu.addItem(header)
            return
        }

        let configMenu = NSMenu()
        configMenu.autoenablesItems = false
        let store = EavesdropperApplicationController.shared.whisperModelStore
        for requirement in model.missingRequirements {
            let item = NSMenuItem(title: requirement.menuTitle, action: nil, keyEquivalent: "")
            item.target = self
            switch requirement {
            case .systemAudioPermission:
                item.action = #selector(openSystemAudioSettings(_:))
            case .whisperModel:
                item.action = #selector(openModelSettings(_:))
            case .whisperModelPreparing:
                item.title = store.statusLine
                item.action = #selector(openModelSettings(_:))
            }
            configMenu.addItem(item)
        }
        header.submenu = configMenu
        menu.addItem(header)
    }

    private static func headerTitle(_ model: MenuHeaderModel) -> NSAttributedString {
        NSAttributedString(
            string: model.title,
            attributes: [
                .foregroundColor: model.tone.nsColor,
                .font: NSFont.menuFont(ofSize: 12),
            ]
        )
    }

    /// Only touches existing items: removing/inserting while the menu tracks is what destabilised AppKit before.
    private func updateOpenMenuInPlace() {
        let app = EavesdropperApplicationController.shared
        let headerModel = app.menuHeader

        if let headerItem, headerModel.shouldShowInMenu, headerModel.isRecording == headerIsRecording {
            headerItem.attributedTitle = Self.headerTitle(headerModel)
            if headerModel.missingRequirements.contains(.whisperModelPreparing),
               let preparing = headerItem.submenu?.items.first(where: { $0.action == #selector(openModelSettings(_:)) }) {
                preparing.title = app.whisperModelStore.statusLine
            }
        }
        if let toggleItem {
            configureToggle(toggleItem, header: headerModel)
        }

        let rows = app.recordingMenuRows
        guard rows.map(\.id) == rowIDs else { return }
        for (item, row) in zip(rowItems, rows) {
            configureRow(item, row: row)
        }
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            guard menu === self.menu else { return }
            EavesdropperApplicationController.shared.whisperModelStore.refreshReadyState()
            rebuildMenu()
        }
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            guard menu === self.menu else { return }
            menuIsOpen = true
        }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            guard menu === self.menu else { return }
            menuIsOpen = false
            updateStatusButton()
        }
    }

    // MARK: - Actions

    @objc private func toggleRecording(_ sender: NSMenuItem) {
        Task {
            await EavesdropperApplicationController.shared.toggleRecording()
        }
    }

    @objc private func openTranscriptionDialog(_ sender: NSMenuItem) {
        guard let sessionURL = sender.representedObject as? URL else { return }
        TranscriptionDialogWindowController.showOrFocus(for: sessionURL)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let folderURL = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folderURL])
    }

    @objc private func openModelSettings(_ sender: NSMenuItem) {
        EavesdropperApplicationController.shared.presentOnboarding()
    }
    
    @objc private func redownloadModel(_ sender: NSMenuItem) {
        EavesdropperApplicationController.shared.prepareRedownloadOnboarding()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        guard let message = LaunchAtLogin.toggle() else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Failed to change login item"
        alert.informativeText = message
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func openRecordingsFolder(_ sender: NSMenuItem) {
        RecordingsLocation.openRootInFinder()
    }

    @objc private func openSystemAudioSettings(_ sender: NSMenuItem) {
        PrivacySettings.openSystemAudioRecording()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        EavesdropperApplicationController.shared.quit()
    }
}
