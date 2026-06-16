import AppKit
import ApplicationServices
import Foundation

public enum SelectionError: Error, Equatable {
    case noSelection
    case accessibilityPermissionMissing
    case clipboardRestoreFailed
}

public struct SelectionService {
    private enum WebAccessibility {
        static let selectedTextMarkerRangeAttribute = "AXSelectedTextMarkerRange" as CFString
        static let attributedStringForTextMarkerRangeParameterizedAttribute = "AXAttributedStringForTextMarkerRange" as CFString
    }

    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    static func preferredAccessibilitySelection(
        markerText: String?,
        rangeText: String?,
        selectedText: String?
    ) -> String? {
        [markerText, rangeText, selectedText].first { text in
            guard let text else {
                return false
            }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? nil
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
        let focusedElement = focused as! AXUIElement
        let markerText = readWebTextMarkerSelection(from: focusedElement)
        let rangeText = readTextRangeSelection(from: focusedElement)
        let selectedText = readSelectedTextAttribute(from: focusedElement)
        return Self.preferredAccessibilitySelection(
            markerText: markerText,
            rangeText: rangeText,
            selectedText: selectedText
        )
    }

    @MainActor
    private func readWebTextMarkerSelection(from element: AXUIElement) -> String? {
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            WebAccessibility.selectedTextMarkerRangeAttribute,
            &markerRange
        ) == .success, let markerRange else {
            return nil
        }

        var attributedText: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            WebAccessibility.attributedStringForTextMarkerRangeParameterizedAttribute,
            markerRange,
            &attributedText
        ) == .success else {
            return nil
        }
        return (attributedText as? NSAttributedString)?.string
    }

    @MainActor
    private func readTextRangeSelection(from element: AXUIElement) -> String? {
        var selectedRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        ) == .success, let selectedRange else {
            return nil
        }

        var selectedText: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            selectedRange,
            &selectedText
        ) == .success else {
            return nil
        }
        return selectedText as? String
    }

    @MainActor
    private func readSelectedTextAttribute(from element: AXUIElement) -> String? {
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success else {
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
