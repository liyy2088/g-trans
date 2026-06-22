import AppKit
import SwiftUI

enum PanelMode {
    case manualInput
    case result
}

@MainActor
final class PanelCoordinator {
    private var panel: NSPanel?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func focusExistingPanel() -> Bool {
        guard isVisible else {
            return false
        }
        bringToFront()
        return true
    }

    func show(appState: AppState, mode: PanelMode) {
        NSApp.setActivationPolicy(.regular)
        if panel == nil {
            let panel = EscapeClosingPanel(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "G-Trans"
            panel.isFloatingPanel = false
            panel.level = .normal
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.onEscape = { [weak appState] in
                appState?.requestClosePanel()
            }
            panel.onClose = { [weak appState] in
                appState?.requestClosePanel()
            }
            self.panel = panel
        }

        panel?.contentView = NSHostingView(rootView: TranslationPanelView(appState: appState, initialMode: mode))
        panel?.center()
        bringToFront()
    }

    func bringToFront() {
        NSApp.setActivationPolicy(.regular)
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        guard let panel else {
            return
        }
        panel.contentView = nil
        panel.orderOut(nil)
        self.panel = nil
    }
}

private final class EscapeClosingPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func close() {
        onClose?()
    }
}
