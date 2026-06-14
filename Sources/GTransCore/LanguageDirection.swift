import Foundation

public enum LanguageDirection {
    public static func targetLanguage(for sourceText: String, defaultTarget: TargetLanguage) -> TargetLanguage {
        let containsChinese = sourceText.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }

        switch defaultTarget {
        case .simplifiedChinese where containsChinese:
            return .english
        case .english where isMostlyEnglish(sourceText):
            return .simplifiedChinese
        default:
            return defaultTarget
        }
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
