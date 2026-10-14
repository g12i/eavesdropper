import AppKit

@MainActor
final class TapScribeStatusMenuController: NSObject, NSMenuDelegate {
    static let shared = TapScribeStatusMenuController()

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

        let isRecording = TapScribeApplicationController.shared.isRecording
        guard displayedRecordingState != isRecording else { return }
        displayedRecordingState = isRecording

        button.image = Self.statusBarImage(isRecording: isRecording)
        button.toolTip = isRecording ? "TapScribe — nagrywanie" : "TapScribe"
    }

    private static func statusBarImage(isRecording: Bool) -> NSImage? {
        if isRecording {
            let palette = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
                .applying(statusSymbolConfiguration)
            let base = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "TapScribe — nagrywanie")
            return base?.withSymbolConfiguration(palette) ?? base
        }

        guard let base = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "TapScribe") else {
            return nil
        }
        let image = base.withSymbolConfiguration(statusSymbolConfiguration) ?? base
        image.isTemplate = true
        return image
    }

    // MARK: - Menu construction

    private func rebuildMenu() {
        let app = TapScribeApplicationController.shared
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
            let empty = NSMenuItem(title: "Brak nagrań", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for row in rows {
                let item = NSMenuItem(title: "", action: #selector(revealInFinder(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = row.url
                configureRow(item, row: row)
                menu.addItem(item)
                rowItems.append(item)
            }
            rowIDs = rows.map(\.id)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Ustawienia", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.autoenablesItems = false
        addItem(to: settingsMenu, title: "Model transkrypcji…", action: #selector(openModelSettings(_:)))
        let redownload = addItem(to: settingsMenu, title: "Pobierz ponownie model…", action: #selector(redownloadModel(_:)))
        redownload.isEnabled = !app.isTranscribing && !app.whisperModelStore.isBusy
        settingsMenu.addItem(.separator())
        addItem(to: settingsMenu, title: "Dźwięk systemu (TCC)…", action: #selector(openSystemAudioSettings(_:)))
        settings.submenu = settingsMenu
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Zakończ", action: #selector(quit(_:)), keyEquivalent: "q")
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
        let app = TapScribeApplicationController.shared
        item.title = app.isRecording ? "Zakończ nagrywanie" : "Start nagrywania"
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
        let store = TapScribeApplicationController.shared.whisperModelStore
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
        let app = TapScribeApplicationController.shared
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
            TapScribeApplicationController.shared.whisperModelStore.refreshReadyState()
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
        TapScribeApplicationController.shared.prepareRedownloadOnboarding()
    }

    @objc private func openSystemAudioSettings(_ sender: NSMenuItem) {
        PrivacySettings.openSystemAudioRecording()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        TapScribeApplicationController.shared.quit()
    }
}
