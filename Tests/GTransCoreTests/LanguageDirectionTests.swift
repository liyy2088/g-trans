import XCTest
@testable import GTransCore

final class LanguageDirectionTests: XCTestCase {
    func nonChineseUsesSimplifiedChineseDefault() {
        XCTAssertEqual(LanguageDirection.targetLanguage(for: "Hello world", defaultTarget: .simplifiedChinese), .simplifiedChinese)
    }

    func simplifiedChineseInputSwitchesToEnglish() {
        XCTAssertEqual(LanguageDirection.targetLanguage(for: "你好世界", defaultTarget: .simplifiedChinese), .english)
    }

    func englishInputWithEnglishDefaultSwitchesToChinese() {
        XCTAssertEqual(LanguageDirection.targetLanguage(for: "Hello world", defaultTarget: .english), .simplifiedChinese)
    }
}
