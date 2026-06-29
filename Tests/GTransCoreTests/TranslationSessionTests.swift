import XCTest
@testable import GTransCore

@MainActor
final class TranslationSessionTests: XCTestCase {
    func closeClearsCurrentContext() {
        let session = TranslationSession(sourceText: "Hello", targetLanguage: .simplifiedChinese)
        session.translation = "你好"
        session.keywordExplanation = "Hello — 你好 — 问候语 — 你好"
        session.followUps = [FollowUpTurn(question: "解释用法", answer: "问候语")]
        session.runTranslation(
            client: LLMClient(session: ContextSnapshotStubURLSession()),
            profile: testProfile,
            streamingEnabled: true
        )
        XCTAssertNotNil(session.lastLLMContextSnapshot)

        session.close()

        XCTAssertTrue(session.sourceText.isEmpty)
        XCTAssertTrue(session.translation.isEmpty)
        XCTAssertTrue(session.keywordExplanation.isEmpty)
        XCTAssertTrue(session.followUps.isEmpty)
        XCTAssertNil(session.activeFollowUpQuestion)
        XCTAssertNil(session.lastLLMContextSnapshot)
        XCTAssertTrue(session.isClosed)
    }

    func startResetsFollowUpsAndTranslation() {
        let session = TranslationSession(sourceText: "Hello", targetLanguage: .simplifiedChinese)
        session.translation = "你好"
        session.keywordExplanation = "Hello — 你好 — 问候语 — 你好"
        session.followUps = [FollowUpTurn(question: "解释用法", answer: "问候语")]
        session.runTranslation(
            client: LLMClient(session: ContextSnapshotStubURLSession()),
            profile: testProfile,
            streamingEnabled: true
        )
        XCTAssertNotNil(session.lastLLMContextSnapshot)

        session.start(sourceText: "Good morning", targetLanguage: .simplifiedChinese)

        XCTAssertEqual(session.sourceText, "Good morning")
        XCTAssertTrue(session.translation.isEmpty)
        XCTAssertTrue(session.keywordExplanation.isEmpty)
        XCTAssertTrue(session.followUps.isEmpty)
        XCTAssertNil(session.activeFollowUpQuestion)
        XCTAssertNil(session.lastLLMContextSnapshot)
        XCTAssertEqual(session.state, .idle)
    }

    func runTranslationStoresLLMContextSnapshot() throws {
        let session = TranslationSession(sourceText: "Hello", targetLanguage: .simplifiedChinese)
        let expectedMessages = PromptBuilder.translationMessages(
            sourceText: "Hello",
            targetLanguage: .simplifiedChinese
        )

        session.runTranslation(
            client: LLMClient(session: ContextSnapshotStubURLSession()),
            profile: testProfile,
            streamingEnabled: true
        )

        let snapshot = try XCTUnwrap(session.lastLLMContextSnapshot)
        XCTAssertEqual(snapshot.requestKind, .translation)
        XCTAssertEqual(snapshot.profileName, "本地 Ollama")
        XCTAssertEqual(snapshot.baseURL.absoluteString, "http://localhost:11434/v1/")
        XCTAssertEqual(snapshot.model, "gemma4:12b-mlx")
        XCTAssertTrue(snapshot.streamingEnabled)
        XCTAssertEqual(snapshot.targetLanguage, .simplifiedChinese)
        XCTAssertEqual(snapshot.messages, expectedMessages)
        XCTAssertEqual(snapshot.sessionSummary.sourceText, "Hello")
        XCTAssertTrue(snapshot.sessionSummary.keywordExplanation.isEmpty)
        XCTAssertFalse(snapshot.jsonString().contains("secret-token"))
    }

    func runTranslationRequestsKeywordExplanationAfterTranslation() async throws {
        let sourceText = "The product team needs a clear threshold before rolling out the experiment."
        let session = TranslationSession(sourceText: sourceText, targetLanguage: .simplifiedChinese)

        session.runTranslation(
            client: LLMClient(session: KeywordExplanationStubURLSession()),
            profile: testProfile,
            streamingEnabled: false
        )

        try await waitForKeywordExplanation(in: session)

        XCTAssertEqual(session.translation, "按时间顺序的")
        XCTAssertEqual(session.keywordExplanation, "chronological — 按时间顺序排列的 — 常用于历史记录、报告、事件列表 — 按时间顺序的")
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.lastLLMContextSnapshot?.requestKind, .keywordExplanation)
        XCTAssertEqual(session.lastLLMContextSnapshot?.messages, PromptBuilder.keywordExplanationMessages(
            sourceText: sourceText,
            translation: "按时间顺序的",
            targetLanguage: .simplifiedChinese
        ))
    }

    func runTranslationRequestsKeywordExplanationForShortText() async throws {
        let session = TranslationSession(sourceText: "Chronological", targetLanguage: .simplifiedChinese)

        session.runTranslation(
            client: LLMClient(session: KeywordExplanationStubURLSession()),
            profile: testProfile,
            streamingEnabled: false
        )

        try await waitForKeywordExplanation(in: session)

        XCTAssertEqual(session.translation, "按时间顺序的")
        XCTAssertEqual(session.keywordExplanation, "chronological — 按时间顺序排列的 — 常用于历史记录、报告、事件列表 — 按时间顺序的")
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.lastLLMContextSnapshot?.requestKind, .keywordExplanation)
    }

    func askStoresFollowUpLLMContextSnapshot() throws {
        let session = TranslationSession(sourceText: "threshold", targetLanguage: .simplifiedChinese)
        session.translation = "阈值"

        session.ask(
            question: PromptBuilder.quickFollowUpQuestion(for: "解释用法", targetLanguage: .simplifiedChinese),
            displayQuestion: "解释用法",
            client: LLMClient(session: ContextSnapshotStubURLSession()),
            profile: testProfile,
            streamingEnabled: false
        )

        let snapshot = try XCTUnwrap(session.lastLLMContextSnapshot)
        XCTAssertEqual(snapshot.requestKind, .followUp)
        XCTAssertFalse(snapshot.streamingEnabled)
        XCTAssertFalse(snapshot.messages.contains(ChatMessage(role: "user", content: "解释用法")))
        XCTAssertFalse(snapshot.messages.contains(ChatMessage(role: "assistant", content: "")))
        XCTAssertEqual(snapshot.messages.last, ChatMessage(role: "user", content: "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。"))
        XCTAssertEqual(
            snapshot.sessionSummary.followUps,
            [
                FollowUpTurn(
                    question: "解释用法",
                    llmQuestion: "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。",
                    answer: ""
                )
            ]
        )
        XCTAssertFalse(snapshot.jsonString().contains("secret-token"))
        XCTAssertTrue(snapshot.plainTextDescription().contains("Messages:"))
    }

    func askReplaysPreviousModelQuestionInFollowUpHistory() {
        let session = TranslationSession(sourceText: "threshold", targetLanguage: .simplifiedChinese)
        session.translation = "阈值"
        session.followUps = [
            FollowUpTurn(
                question: "解释用法",
                llmQuestion: "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。",
                answer: "表示触发某件事的界限。"
            )
        ]

        session.ask(
            question: "再给两个例句",
            client: LLMClient(session: ContextSnapshotStubURLSession()),
            profile: testProfile,
            streamingEnabled: false
        )

        let snapshot = session.lastLLMContextSnapshot
        XCTAssertTrue(snapshot?.messages.contains(ChatMessage(role: "user", content: "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。")) == true)
        XCTAssertFalse(snapshot?.messages.contains(ChatMessage(role: "user", content: "解释用法")) == true)
        XCTAssertTrue(snapshot?.messages.contains(ChatMessage(role: "assistant", content: "表示触发某件事的界限。")) == true)
        XCTAssertEqual(snapshot?.messages.last, ChatMessage(role: "user", content: "再给两个例句"))
    }

    func askAddsAssistantResponseToLLMContextSnapshot() async throws {
        let session = TranslationSession(sourceText: "threshold", targetLanguage: .simplifiedChinese)
        session.translation = "阈值"

        session.ask(
            question: PromptBuilder.quickFollowUpQuestion(for: "解释用法", targetLanguage: .simplifiedChinese),
            displayQuestion: "解释用法",
            client: LLMClient(session: ContextSnapshotStubURLSession()),
            profile: testProfile,
            streamingEnabled: false
        )

        try await waitForContextAssistantResponse(in: session)

        let snapshot = try XCTUnwrap(session.lastLLMContextSnapshot)
        XCTAssertEqual(snapshot.messages.last, ChatMessage(role: "assistant", content: "回答"))
    }

    private func waitForContextAssistantResponse(in session: TranslationSession) async throws {
        for _ in 0..<20 {
            if session.lastLLMContextSnapshot?.messages.last == ChatMessage(role: "assistant", content: "回答") {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for context assistant response")
    }

    private func waitForKeywordExplanation(in session: TranslationSession) async throws {
        for _ in 0..<20 {
            if !session.keywordExplanation.isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for keyword explanation")
    }

    private var testProfile: LLMProfile {
        LLMProfile(
            name: "本地 Ollama",
            baseURL: URL(string: "http://localhost:11434/v1/")!,
            apiKey: "secret-token",
            model: "gemma4:12b-mlx"
        )
    }
}

private final class ContextSnapshotStubURLSession: URLSessionProtocol, @unchecked Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
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
        AsyncThrowingStream { continuation in
            continuation.yield(#"data: {"choices":[{"delta":{"content":"回答"}}]}"#)
            continuation.yield("data: [DONE]")
            continuation.finish()
        }
    }
}

private final class KeywordExplanationStubURLSession: URLSessionProtocol, @unchecked Sendable {
    private var requestCount = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        let content: String
        if requestCount == 1 {
            content = "按时间顺序的"
        } else {
            content = "chronological — 按时间顺序排列的 — 常用于历史记录、报告、事件列表 — 按时间顺序的"
        }
        let data = Data(#"{"choices":[{"message":{"content":"\#(content)"}}]}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func lines(for request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
