import Foundation

public enum LanguageDirection {
    public static func targetLanguage(for sourceText: String, defaultTarget: TargetLanguage) -> TargetLanguage {
        let scalars = sourceText.unicodeScalars
        let containsCJKIdeograph = scalars.contains(where: isCJKIdeograph)
        let containsJapaneseKana = scalars.contains(where: isJapaneseKana)
        let containsChinese = containsCJKIdeograph && !containsJapaneseKana

        switch defaultTarget {
        case .simplifiedChinese where containsChinese:
            return .english
        case .english where isMostlyEnglish(sourceText):
            return .simplifiedChinese
        default:
            return defaultTarget
        }
    }

    private static func isCJKIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(Int(scalar.value))
    }

    private static func isJapaneseKana(_ scalar: Unicode.Scalar) -> Bool {
        let value = Int(scalar.value)
        return (0x3040...0x309F).contains(value) ||
            (0x30A0...0x30FF).contains(value) ||
            (0x31F0...0x31FF).contains(value) ||
            (0xFF65...0xFF9F).contains(value)
    }

    private static func isMostlyEnglish(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else {
            return false
        }
        let asciiLetters = letters.filter { $0.isASCII }
        return Double(asciiLetters.count) / Double(letters.count) >= 0.8
    }
}
