import AppKit
import ApplicationServices
import Foundation

public enum SelectionError: Error, Equatable {
    case noSelection
    case accessibilityPermissionMissing
    case clipboardRestoreFailed
}

public struct SelectionService {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    @MainActor
    public func readSelectedText() async throws -> String {
        let isAccessibilityTrusted = accessibilityTrusted(prompt: false)
        if isAccessibilityTrusted,
           let text = readAccessibilitySelection(),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if let text = try await readViaClipboardFallback(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if !isAccessibilityTrusted {
            throw SelectionError.accessibilityPermissionMissing
        }
        throw SelectionError.noSelection
    }

    @MainActor
    public func accessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    private func readAccessibilitySelection() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else {
            return nil
        }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success else {
            return nil
        }
        return selected as? String
    }

    @MainActor
    private func readViaClipboardFallback() async throws -> String? {
        let oldString = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        var text: String?
        for _ in 0..<16 {
            try await Task.sleep(nanoseconds: 50_000_000)
            guard pasteboard.changeCount != oldChangeCount else {
                continue
            }
            text = pasteboard.string(forType: .string)
            break
        }
        pasteboard.clearContents()
        guard let oldString else {
            return text
        }
        let restored = pasteboard.setString(oldString, forType: .string)
        if !restored {
            throw SelectionError.clipboardRestoreFailed
        }
        return text
    }
}
