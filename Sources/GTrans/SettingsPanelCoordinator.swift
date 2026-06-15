import AppKit
import SwiftUI

@MainActor
final class SettingsPanelCoordinator: NSObject {
    private var panel: NSPanel?

    func show(appState: AppState) {
        NSApp.setActivationPolicy(.regular)
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "G-Trans 设置"
            panel.isReleasedWhenClosed = false
            panel.center()
            panel.delegate = self
            self.panel = panel
        }
        panel?.contentView = NSHostingView(rootView: SettingsView(appState: appState))
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension SettingsPanelCoordinator: NSWindowDelegate {}
