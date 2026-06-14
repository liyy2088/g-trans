import XCTest
@testable import GTransCore

@MainActor
final class TranslationSessionTests: XCTestCase {
    func closeClearsCurrentContext() {
        let session = TranslationSession(sourceText: "Hello", targetLanguage: .simplifiedChinese)
        session.translation = "你好"
        session.followUps = [FollowUpTurn(question: "解释用法", answer: "问候语")]

        session.close()

        XCTAssertTrue(session.sourceText.isEmpty)
        XCTAssertTrue(session.translation.isEmpty)
        XCTAssertTrue(session.followUps.isEmpty)
        XCTAssertTrue(session.isClosed)
    }

    func startResetsFollowUpsAndTranslation() {
        let session = TranslationSession(sourceText: "Hello", targetLanguage: .simplifiedChinese)
        session.translation = "你好"
        session.followUps = [FollowUpTurn(question: "解释用法", answer: "问候语")]

        session.start(sourceText: "Good morning", targetLanguage: .simplifiedChinese)

        XCTAssertEqual(session.sourceText, "Good morning")
        XCTAssertTrue(session.translation.isEmpty)
        XCTAssertTrue(session.followUps.isEmpty)
        XCTAssertEqual(session.state, .idle)
    }
}
