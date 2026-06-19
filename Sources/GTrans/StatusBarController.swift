import AppKit
import GTransCore

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private weak var appState: AppState?
    private let menu = NSMenu()
    private let accessibilityItem = NSMenuItem()
    private let apiItem = NSMenuItem()

    func install(appState: AppState) {
        self.appState = appState
        if let button = statusItem.button {
            button.image = statusBarIcon()
            button.imagePosition = .imageOnly
        }
        menu.delegate = self
        menu.autoenablesItems = false

        let openItem = NSMenuItem(title: "打开翻译", action: #selector(openTranslation), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        accessibilityItem.isEnabled = false
        apiItem.isEnabled = false
        menu.addItem(accessibilityItem)
        menu.addItem(apiItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateStatusItems()
        AppDiagnostics.info("status_item_installed")
    }

    func menuWillOpen(_ menu: NSMenu) {
        appState?.refreshAccessibilityStatus()
        updateStatusItems()
    }

    private func updateStatusItems() {
        guard let appState else {
            accessibilityItem.title = "辅助功能权限：未知"
            apiItem.title = "API 配置：未知"
            return
        }
        accessibilityItem.title = "辅助功能权限：\(appState.accessibilityEnabled ? "已开启" : "未开启")"
        apiItem.title = "API 配置：\(appState.isAPIConfigured ? "已完成" : "未完成")"
    }

    private func statusBarIcon() -> NSImage? {
        let image = NSImage(named: "GTransMenuBarTemplate")
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: "G-Trans")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        image?.accessibilityDescription = "G-Trans"
        return image
    }

    @objc private func openTranslation() {
        AppDiagnostics.info("status_menu_open_translation")
        appState?.openCurrentTranslationWindow()
    }

    @objc private func openSettings() {
        AppDiagnostics.info("status_menu_open_settings")
        appState?.openSettings()
    }

    @objc private func quit() {
        AppDiagnostics.info("status_menu_quit")
        NSApplication.shared.terminate(nil)
    }
}
