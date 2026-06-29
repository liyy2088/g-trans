import Foundation

public enum TranslationContentPolicy {
    private static let maxReadingWords = 4
    private static let maxReadingCharactersWithoutSpaces = 12
    private static let maxReadingCharacters = 48

    public static func readingOptions(for sourceText: String) -> TranslationReadingOptions {
        isWordOrShortPhrase(sourceText)
            ? .allEnabled
            : TranslationReadingOptions(sourceEnabled: false, translationEnabled: false)
    }

    public static func shouldRequestKeywordExplanation(for sourceText: String) -> Bool {
        let normalized = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty
    }

    private static func isWordOrShortPhrase(_ sourceText: String) -> Bool {
        let normalized = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !normalized.contains(where: { $0.isNewline }),
              normalized.count <= maxReadingCharacters else {
            return false
        }
        let words = wordCount(in: normalized)
        if words > 1 {
            return words <= maxReadingWords
        }
        return nonWhitespaceCharacterCount(in: normalized) <= maxReadingCharactersWithoutSpaces
    }

    private static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private static func nonWhitespaceCharacterCount(in text: String) -> Int {
        text.filter { !$0.isWhitespace }.count
    }
}
