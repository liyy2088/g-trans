import Foundation
import XCTest
@testable import GTransCore

final class PromptBuilderTests: XCTestCase {
    func testFollowUpMessagesDefaultToSourceText() {
        let messages = PromptBuilder.followUpMessages(
            sourceText: "threshold",
            translation: "阈值",
            targetLanguage: .simplifiedChinese,
            history: [],
            question: "再给两个例句"
        )

        XCTAssertTrue(messages[0].content.contains("所有追问默认针对原文"))
        XCTAssertTrue(messages[0].content.contains("译文只作为参考译文"))
        XCTAssertTrue(messages[0].content.contains("只有用户明确询问译文"))
        XCTAssertTrue(messages[1].content.contains("原文：\nthreshold"))
        XCTAssertTrue(messages[1].content.contains("参考译文（简体中文）：\n阈值"))
        XCTAssertEqual(messages.last, ChatMessage(role: "user", content: "再给两个例句"))
    }

    func testSourceFocusedQuickQuestionMapping() {
        XCTAssertEqual(PromptBuilder.sourceFocusedFollowUpQuestion(for: "解释用法"), "请针对原文解释用法。")
        XCTAssertEqual(PromptBuilder.sourceFocusedFollowUpQuestion(for: "给例句"), "请针对原文给例句。")
        XCTAssertEqual(PromptBuilder.sourceFocusedFollowUpQuestion(for: "更自然表达"), "请针对原文给出更自然的表达。")
        XCTAssertEqual(PromptBuilder.sourceFocusedFollowUpQuestion(for: "语法分析"), "请针对原文做语法分析。")
        XCTAssertEqual(PromptBuilder.sourceFocusedFollowUpQuestion(for: "这个译文自然吗"), "这个译文自然吗")
    }

    @MainActor
    func testSessionStoresDisplayQuestionButSendsSourceFocusedQuestion() async throws {
        let urlSession = StubURLSession()
        let client = LLMClient(session: urlSession)
        let profile = LLMProfile(
            baseURL: URL(string: "http://localhost:11434/v1/")!,
            apiKey: "ollama",
            model: "gemma4:12b-mlx"
        )
        let session = TranslationSession(sourceText: "threshold", targetLanguage: .simplifiedChinese)
        session.translation = "阈值"

        session.ask(
            question: PromptBuilder.sourceFocusedFollowUpQuestion(for: "解释用法"),
            displayQuestion: "解释用法",
            client: client,
            profile: profile,
            streamingEnabled: false
        )

        XCTAssertEqual(session.activeFollowUpQuestion, "解释用法")
        XCTAssertEqual(session.followUps, [FollowUpTurn(question: "解释用法", answer: "")])

        try await waitForFollowUpAnswer(in: session)

        XCTAssertEqual(session.followUps, [FollowUpTurn(question: "解释用法", answer: "回答")])
        XCTAssertNil(session.activeFollowUpQuestion)
        let request = try XCTUnwrap(urlSession.lastRequest)
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)
        XCTAssertEqual(decoded.messages.last, ChatMessage(role: "user", content: "请针对原文解释用法。"))
    }

    @MainActor
    private func waitForFollowUpAnswer(in session: TranslationSession) async throws {
        for _ in 0..<20 {
            if session.followUps.last?.answer == "回答" {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for follow-up answer")
    }
}

private final class StubURLSession: URLSessionProtocol, @unchecked Sendable {
    private(set) var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let data = Data(#"{"choices":[{"message":{"content":"回答"}}]}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func lines(for request: URLRequest) -> AsyncThrowingStream<String, Error> {
        lastRequest = request
        return AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
