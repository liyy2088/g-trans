import Foundation
import XCTest
@testable import GTransCore

final class PromptBuilderTests: XCTestCase {
    func testTranslationContentPolicyEnablesReadingOnlyForWordsAndShortPhrases() {
        XCTAssertEqual(TranslationContentPolicy.readingOptions(for: "Good morning"), .allEnabled)
        XCTAssertEqual(TranslationContentPolicy.readingOptions(for: "as soon as possible"), .allEnabled)
        XCTAssertEqual(TranslationContentPolicy.readingOptions(for: "早上好"), .allEnabled)

        let sentenceOptions = TranslationContentPolicy.readingOptions(
            for: "The product team needs a clear threshold before rolling out the experiment."
        )
        XCTAssertFalse(sentenceOptions.sourceEnabled)
        XCTAssertFalse(sentenceOptions.translationEnabled)
    }

    func testTranslationContentPolicyRequestsKeywordsForAnyNonEmptyText() {
        XCTAssertFalse(TranslationContentPolicy.shouldRequestKeywordExplanation(for: ""))
        XCTAssertFalse(TranslationContentPolicy.shouldRequestKeywordExplanation(for: "   "))
        XCTAssertTrue(TranslationContentPolicy.shouldRequestKeywordExplanation(for: "threshold"))
        XCTAssertTrue(TranslationContentPolicy.shouldRequestKeywordExplanation(for: "Good morning"))
        XCTAssertTrue(TranslationContentPolicy.shouldRequestKeywordExplanation(for: "早上好"))

        XCTAssertTrue(TranslationContentPolicy.shouldRequestKeywordExplanation(
            for: "The product team needs a clear threshold before rolling out the experiment."
        ))
        XCTAssertTrue(TranslationContentPolicy.shouldRequestKeywordExplanation(for: "这个实验需要一个明确阈值才能发布给所有用户。"))
    }

    func testTranslationMessagesAskForReadingGuide() {
        let chineseMessages = PromptBuilder.translationMessages(sourceText: "Good morning", targetLanguage: .simplifiedChinese)
        XCTAssertTrue(chineseMessages[0].content.contains("只输出原文读音、译文和译文读音"))
        XCTAssertTrue(chineseMessages[1].content.contains("读音规则：中文用拼音；英文用 IPA 英标；日文用 ふりがな 和 ローマ字；其他语言用常用拉丁转写或 IPA。"))
        XCTAssertTrue(chineseMessages[1].content.contains("原文读音：<按识别出的源语言标注读音>"))
        XCTAssertTrue(chineseMessages[1].content.contains("译文：<简体中文译文>"))
        XCTAssertTrue(chineseMessages[1].content.contains("译文读音：<拼音>"))
        XCTAssertTrue(chineseMessages[1].content.contains("Good morning"))

        let englishMessages = PromptBuilder.translationMessages(sourceText: "你好", targetLanguage: .english)
        XCTAssertTrue(englishMessages[1].content.contains("译文读音：<IPA 英标>"))

        let japaneseMessages = PromptBuilder.translationMessages(sourceText: "Hello", targetLanguage: .japanese)
        XCTAssertTrue(japaneseMessages[1].content.contains("译文读音：<ふりがな；ローマ字>"))
    }

    func testTranslationMessagesOmitDisabledReadingGuides() {
        let sourceOnlyMessages = PromptBuilder.translationMessages(
            sourceText: "Good morning",
            targetLanguage: .simplifiedChinese,
            readingOptions: TranslationReadingOptions(sourceEnabled: true, translationEnabled: false)
        )
        XCTAssertTrue(sourceOnlyMessages[0].content.contains("只输出原文读音和译文"))
        XCTAssertTrue(sourceOnlyMessages[1].content.contains("原文读音：<按识别出的源语言标注读音>"))
        XCTAssertTrue(sourceOnlyMessages[1].content.contains("译文：<简体中文译文>"))
        XCTAssertFalse(sourceOnlyMessages[1].content.contains("译文读音："))

        let translationOnlyMessages = PromptBuilder.translationMessages(
            sourceText: "你好",
            targetLanguage: .english,
            readingOptions: TranslationReadingOptions(sourceEnabled: false, translationEnabled: true)
        )
        XCTAssertTrue(translationOnlyMessages[0].content.contains("只输出译文和译文读音"))
        XCTAssertFalse(translationOnlyMessages[1].content.contains("原文读音："))
        XCTAssertTrue(translationOnlyMessages[1].content.contains("译文：<英文译文>"))
        XCTAssertTrue(translationOnlyMessages[1].content.contains("译文读音：<IPA 英标>"))

        let translationOnlyNoReadingMessages = PromptBuilder.translationMessages(
            sourceText: "Hello",
            targetLanguage: .japanese,
            readingOptions: TranslationReadingOptions(sourceEnabled: false, translationEnabled: false)
        )
        XCTAssertTrue(translationOnlyNoReadingMessages[0].content.contains("只输出译文，不解释，不加引号。"))
        XCTAssertFalse(translationOnlyNoReadingMessages[1].content.contains("读音规则："))
        XCTAssertFalse(translationOnlyNoReadingMessages[1].content.contains("原文读音："))
        XCTAssertTrue(translationOnlyNoReadingMessages[1].content.contains("译文：<日文译文>"))
        XCTAssertFalse(translationOnlyNoReadingMessages[1].content.contains("译文读音："))
    }

    func testFollowUpMessagesDefaultToSourceText() {
        let messages = PromptBuilder.followUpMessages(
            sourceText: "threshold",
            translation: "阈值",
            targetLanguage: .simplifiedChinese,
            history: [],
            question: "再给两个例句"
        )

        XCTAssertTrue(messages[0].content.contains("所有追问默认针对原文"))
        XCTAssertTrue(messages[0].content.contains("参考译文只作为理解辅助"))
        XCTAssertTrue(messages[0].content.contains("明确要求优化译文或目标语言表达"))
        XCTAssertTrue(messages[1].content.contains("原文：\nthreshold"))
        XCTAssertTrue(messages[1].content.contains("参考译文（简体中文）：\n阈值"))
        XCTAssertEqual(messages.last, ChatMessage(role: "user", content: "再给两个例句"))
    }

    func testQuickQuestionMapping() {
        XCTAssertEqual(
            PromptBuilder.quickFollowUpQuestion(for: "解释用法", targetLanguage: .simplifiedChinese),
            "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。"
        )
        XCTAssertEqual(
            PromptBuilder.quickFollowUpQuestion(for: "给例句", targetLanguage: .simplifiedChinese),
            "请针对原文中的核心表达给出 3 个例句，并附上简短说明。不要围绕参考译文造句。"
        )
        XCTAssertEqual(
            PromptBuilder.quickFollowUpQuestion(for: "更自然表达", targetLanguage: .simplifiedChinese),
            "请基于原文和参考译文，给出更自然的简体中文表达。只输出改写后的简体中文译文；不要解释，不要分析原文。"
        )
        XCTAssertEqual(
            PromptBuilder.quickFollowUpQuestion(for: "语法分析", targetLanguage: .simplifiedChinese),
            "请针对原文做语法分析，说明句子结构、关键成分和容易误解的点。不要分析参考译文，除非它影响理解。"
        )
        XCTAssertEqual(
            PromptBuilder.quickFollowUpQuestion(for: "这个译文自然吗", targetLanguage: .simplifiedChinese),
            "这个译文自然吗"
        )
    }

    func testKeywordExplanationMessagesTargetSourceText() {
        let messages = PromptBuilder.keywordExplanationMessages(
            sourceText: "The product team needs a clear threshold before rolling out the experiment.",
            translation: "产品团队需要一个明确的阈值，才能推出这个实验。",
            targetLanguage: .simplifiedChinese
        )

        XCTAssertTrue(messages[0].content.contains("只针对原文解释关键词汇"))
        XCTAssertTrue(messages[0].content.contains("参考译文只作为理解辅助"))
        XCTAssertTrue(messages[0].content.contains("只把“译文：”字段作为参考"))
        XCTAssertTrue(messages[0].content.contains("使用简体中文"))
        XCTAssertTrue(messages[1].content.contains("尽量找出所有值得解释的关键词或短语"))
        XCTAssertTrue(messages[1].content.contains("由你根据原文复杂度决定解释数量"))
        XCTAssertTrue(messages[1].content.contains("原词/短语 — 含义 — 语境或用法 — 常见译法"))
        XCTAssertTrue(messages[1].content.contains("无需要特别解释的关键词汇"))
        XCTAssertTrue(messages[1].content.contains("原文：\nThe product team needs a clear threshold before rolling out the experiment."))
        XCTAssertTrue(messages[1].content.contains("参考译文（简体中文）：\n产品团队需要一个明确的阈值，才能推出这个实验。"))
    }

    func testFollowUpMessagesReplayModelQuestionFromHistory() {
        let messages = PromptBuilder.followUpMessages(
            sourceText: "threshold",
            translation: "阈值",
            targetLanguage: .simplifiedChinese,
            history: [
                FollowUpTurn(
                    question: "解释用法",
                    llmQuestion: "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。",
                    answer: "表示触发某件事的界限。"
                )
            ],
            question: "再给两个例句"
        )

        XCTAssertTrue(messages.contains(ChatMessage(role: "user", content: "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。")))
        XCTAssertFalse(messages.contains(ChatMessage(role: "user", content: "解释用法")))
        XCTAssertTrue(messages.contains(ChatMessage(role: "assistant", content: "表示触发某件事的界限。")))
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
            question: PromptBuilder.quickFollowUpQuestion(for: "解释用法", targetLanguage: .simplifiedChinese),
            displayQuestion: "解释用法",
            client: client,
            profile: profile,
            streamingEnabled: false
        )

        XCTAssertEqual(session.activeFollowUpQuestion, "解释用法")
        XCTAssertEqual(
            session.followUps,
            [
                FollowUpTurn(
                    question: "解释用法",
                    llmQuestion: "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。",
                    answer: ""
                )
            ]
        )

        try await waitForFollowUpAnswer(in: session)

        XCTAssertEqual(
            session.followUps,
            [
                FollowUpTurn(
                    question: "解释用法",
                    llmQuestion: "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。",
                    answer: "回答"
                )
            ]
        )
        XCTAssertNil(session.activeFollowUpQuestion)
        let request = try XCTUnwrap(urlSession.lastRequest)
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)
        XCTAssertFalse(decoded.messages.contains(ChatMessage(role: "user", content: "解释用法")))
        XCTAssertFalse(decoded.messages.contains(ChatMessage(role: "assistant", content: "")))
        XCTAssertEqual(decoded.messages.last, ChatMessage(role: "user", content: "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。"))
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
