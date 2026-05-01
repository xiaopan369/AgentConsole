import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private weak var appState: AppState?

    func configure(appState: AppState) {
        self.appState = appState
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = makeStatusImage()
            item.button?.imagePosition = .imageOnly
            item.button?.toolTip = "Agent Console"
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let appState else { return }
        let isChinese = appState.appLanguage == .zhHans
        let hasSession = appState.hasSessionSelection

        menu.addItem(makeItem(
            title: isChinese ? "打开 Agent Console" : "Open Agent Console",
            action: #selector(openAgentConsole)
        ))
        menu.addItem(.separator())
        menu.addItem(makeItem(
            title: appState.strings.importProject,
            action: #selector(importProject)
        ))
        menu.addItem(makeItem(
            title: isChinese ? "一键更新交接文件" : "Update Handoff Now",
            action: #selector(updateHandoff),
            isEnabled: hasSession
        ))
        menu.addItem(.separator())
        menu.addItem(makeItem(
            title: appState.strings.switchToClaude,
            action: #selector(switchToClaude),
            isEnabled: hasSession
        ))
        menu.addItem(makeItem(
            title: appState.strings.switchToCodex,
            action: #selector(switchToCodex),
            isEnabled: hasSession
        ))
        menu.addItem(.separator())
        menu.addItem(makeItem(
            title: appState.strings.openSettings,
            action: #selector(openSettings)
        ))
        menu.addItem(makeItem(
            title: isChinese ? "退出 Agent Console" : "Quit Agent Console",
            action: #selector(quitAgentConsole)
        ))
    }

    private func makeItem(title: String, action: Selector, isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        return item
    }

    private func makeStatusImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image: NSImage
        if let resourceImage = makeResourceImage(named: "MenuBarLogo", size: size, isTemplate: false) {
            image = resourceImage
        } else if let resourceImage = makeResourceImage(named: "AppMiniwindow", size: size, isTemplate: false) {
            image = resourceImage
        } else if let resourceImage = makeResourceImage(named: "MenuBarTemplate", size: size, isTemplate: true) {
            image = resourceImage
        } else if let symbolImage = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Agent Console") {
            image = symbolImage
        } else {
            image = NSImage(size: size)
        }
        image.size = size
        return image
    }

    private func makeResourceImage(named name: String, size: NSSize, isTemplate: Bool) -> NSImage? {
        let image = NSImage(size: size)
        var loadedRepresentation = false

        for (resourceName, pointSize) in [(name, size), ("\(name)@2x", size)] {
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let representation = NSBitmapImageRep(data: data) else {
                continue
            }
            representation.size = pointSize
            image.addRepresentation(representation)
            loadedRepresentation = true
        }

        guard loadedRepresentation else { return nil }
        image.isTemplate = isTemplate
        return image
    }

    @objc private func openAgentConsole() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Agent Console" }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func importProject() {
        openAgentConsole()
        appState?.importSingleProject()
    }

    @objc private func updateHandoff() {
        openAgentConsole()
        appState?.syncCurrentStateToHandoff()
    }

    @objc private func switchToClaude() {
        openAgentConsole()
        appState?.switchToAgent(.claude)
    }

    @objc private func switchToCodex() {
        openAgentConsole()
        appState?.switchToAgent(.codex)
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quitAgentConsole() {
        NSApp.terminate(nil)
    }
}
