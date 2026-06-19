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
        static let stringForTextMarkerRangeParameterizedAttribute = "AXStringForTextMarkerRange" as CFString
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
        if let markerText = nonEmpty(markerText) {
            return markerText
        }

        let selectedText = nonEmpty(selectedText)
        let rangeText = nonEmpty(rangeText)
        if let selectedText {
            if let rangeText, shouldPreferRangeText(rangeText, over: selectedText) {
                return rangeText
            }
            return selectedText
        }

        return rangeText
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    private static func shouldPreferRangeText(_ rangeText: String, over selectedText: String) -> Bool {
        rangeText.contains(where: \.isNewline)
            && !selectedText.contains(where: \.isNewline)
            && collapsedWhitespace(rangeText) == collapsedWhitespace(selectedText)
    }

    private static func collapsedWhitespace(_ text: String) -> String {
        text.unicodeScalars
            .lazy
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
            .map(String.init)
            .joined()
    }

    @MainActor
    public func readSelectedText(
        in application: NSRunningApplication? = nil,
        afterClipboardFallbackPosted: (@MainActor () -> Void)? = nil
    ) async throws -> String {
        let isAccessibilityTrusted = accessibilityTrusted(prompt: false)
        if isAccessibilityTrusted,
           let text = readAccessibilitySelection(in: application),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if let text = try await readViaClipboardFallback(afterPosted: afterClipboardFallbackPosted),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
    private func readAccessibilitySelection(in application: NSRunningApplication?) -> String? {
        if let application,
           let text = readFocusedSelection(from: application) {
            return text
        }
        if let text = readSystemFocusedSelection() {
            return text
        }
        return readFrontmostApplicationFocusedSelection()
    }

    @MainActor
    private func readSystemFocusedSelection() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else {
            return nil
        }
        return readSelectionNear(focused as! AXUIElement)
    }

    @MainActor
    private func readFrontmostApplicationFocusedSelection() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return readFocusedSelection(from: app)
    }

    @MainActor
    private func readFocusedSelection(from application: NSRunningApplication) -> String? {
        let element = AXUIElementCreateApplication(application.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else {
            return readSelectionFromDescendants(of: element, maxDepth: 6, maxElements: 160)
        }
        if let text = readSelectionNear(focused as! AXUIElement) {
            return text
        }
        return readSelectionFromDescendants(of: element, maxDepth: 6, maxElements: 160)
    }

    @MainActor
    private func readSelectionNear(_ element: AXUIElement) -> String? {
        if let text = readSelection(from: element) {
            return text
        }
        if let text = readSelectionFromAncestors(of: element) {
            return text
        }
        return readSelectionFromDescendants(of: element, maxDepth: 4, maxElements: 80)
    }

    @MainActor
    private func readSelectionFromAncestors(of element: AXUIElement, maxDepth: Int = 4) -> String? {
        var current = element
        for _ in 0..<maxDepth {
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent else {
                return nil
            }
            let parentElement = parent as! AXUIElement
            if let text = readSelection(from: parentElement) {
                return text
            }
            current = parentElement
        }
        return nil
    }

    @MainActor
    private func readSelectionFromDescendants(of root: AXUIElement, maxDepth: Int, maxElements: Int) -> String? {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var visited = Set<CFHashCode>()
        var inspected = 0

        while !queue.isEmpty, inspected < maxElements {
            let item = queue.removeFirst()
            guard visited.insert(CFHash(item.element)).inserted else {
                continue
            }
            inspected += 1

            if item.depth > 0, let text = readSelection(from: item.element) {
                return text
            }
            guard item.depth < maxDepth else {
                continue
            }
            for child in childElements(of: item.element) {
                queue.append((child, item.depth + 1))
            }
        }
        return nil
    }

    @MainActor
    private func childElements(of element: AXUIElement) -> [AXUIElement] {
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let children else {
            return []
        }
        return children as? [AXUIElement] ?? []
    }

    @MainActor
    private func readSelection(from focusedElement: AXUIElement) -> String? {
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
            var plainText: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                element,
                WebAccessibility.stringForTextMarkerRangeParameterizedAttribute,
                markerRange,
                &plainText
            ) == .success else {
                return nil
            }
            return plainText as? String
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
    private func readViaClipboardFallback(afterPosted: (@MainActor () -> Void)?) async throws -> String? {
        let oldString = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        afterPosted?()

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
