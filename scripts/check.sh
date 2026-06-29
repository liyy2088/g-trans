#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/direct-check"
HARNESS="$BUILD_DIR/LogicCheck.swift"
BIN="$BUILD_DIR/logic-check"

cleanup() {
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR"

swiftc -parse-as-library -typecheck "$ROOT_DIR"/Sources/GTransCore/*.swift
swiftc \
  -parse-as-library \
  -emit-module \
  -module-name GTransCore \
  "$ROOT_DIR"/Sources/GTransCore/*.swift \
  -emit-module-path "$BUILD_DIR/GTransCore.swiftmodule"
swiftc \
  -parse-as-library \
  -typecheck \
  -I "$BUILD_DIR" \
  "$ROOT_DIR"/Sources/GTrans/*.swift

cat > "$HARNESS" <<'SWIFT'
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

final class DirectCheckURLSession: URLSessionProtocol, @unchecked Sendable {
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

@main
struct LogicCheck {
    static func main() async throws {
        expect(LanguageDirection.targetLanguage(for: "Hello world", defaultTarget: .simplifiedChinese) == .simplifiedChinese, "English should translate to Simplified Chinese by default")
        expect(LanguageDirection.targetLanguage(for: "你好世界", defaultTarget: .simplifiedChinese) == .english, "Simplified Chinese should switch to English")
        expect(LanguageDirection.targetLanguage(for: "今日は良い天気です", defaultTarget: .simplifiedChinese) == .simplifiedChinese, "Japanese should keep Simplified Chinese target by default")
        expect(LanguageDirection.targetLanguage(for: "Hello world", defaultTarget: .english) == .simplifiedChinese, "English default should switch to Simplified Chinese for English source")

        let suiteName = "GTransDirectCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsConfigurationStore(defaults: defaults)
        let storedProfile = LLMProfile(id: "local", name: "本地", apiKey: "ollama", model: "local-model")
        let storedConfiguration = AppConfiguration(
            targetLanguage: .english,
            streamingEnabled: false,
            sourceReadingEnabled: false,
            translationReadingEnabled: true,
            launchAtLogin: true,
            selectedProfileID: storedProfile.id,
            profiles: [storedProfile]
        )
        store.save(storedConfiguration)
        expect(store.load() == storedConfiguration, "reading settings round trip")

        let legacySuiteName = "GTransDirectCheckLegacy.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuiteName)!
        defer { legacyDefaults.removePersistentDomain(forName: legacySuiteName) }
        legacyDefaults.set("http://localhost:11434/v1/", forKey: "baseURL")
        legacyDefaults.set("gemma4:12b-mlx", forKey: "model")
        legacyDefaults.set("ollama", forKey: "apiKey")
        let legacyConfiguration = UserDefaultsConfigurationStore(defaults: legacyDefaults).load()
        expect(legacyConfiguration.sourceReadingEnabled, "legacy source reading defaults enabled")
        expect(legacyConfiguration.translationReadingEnabled, "legacy translation reading defaults enabled")

        let client = LLMClient()
        let profile = LLMProfile(
            baseURL: URL(string: "http://localhost:11434/v1/")!,
            apiKey: "ollama",
            model: "qwen3.5:2b-mlx"
        )
        let request = try client.makeRequest(
            profile: profile,
            messages: [ChatMessage(role: "user", content: "Hi")],
            stream: true
        )
        expect(request.url?.absoluteString == "http://localhost:11434/v1/chat/completions", "request URL")
        expect(request.httpMethod == "POST", "HTTP method")
        expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ollama", "authorization header")
        let body = try JSONDecoder().decode(ChatCompletionRequest.self, from: request.httpBody!)
        expect(body.model == "qwen3.5:2b-mlx", "model")
        expect(body.stream == true, "stream flag")
        expect(body.temperature == 0, "temperature")
        expect(body.maxTokens == 2048, "max tokens")
        expect(body.maxCompletionTokens == nil, "max completion tokens omitted")
        expect(body.reasoning == ReasoningConfig(effort: "none"), "reasoning disabled")

        let reasoningProfile = LLMProfile(
            baseURL: URL(string: "https://api.example.com/v1/")!,
            apiKey: "token",
            model: "gpt-5-example"
        )
        let reasoningRequest = try client.makeRequest(
            profile: reasoningProfile,
            messages: [ChatMessage(role: "user", content: "Hi")],
            stream: false
        )
        let reasoningBody = try JSONDecoder().decode(ChatCompletionRequest.self, from: reasoningRequest.httpBody!)
        expect(reasoningBody.maxTokens == nil, "reasoning max tokens omitted")
        expect(reasoningBody.maxCompletionTokens == 2048, "reasoning max completion tokens")

        var parser = StreamingChatParser()
        let firstToken = try parser.parse(line: #"data: {"choices":[{"delta":{"content":"你"}}]}"#)
        let secondToken = try parser.parse(line: #"data: {"choices":[{"delta":{"content":"好"}}]}"#)
        let tokenLimit = try parser.parse(line: #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#)
        let done = try parser.parse(line: "data: [DONE]")
        expect(firstToken == ["你"], "first SSE token")
        expect(secondToken == ["好"], "second SSE token")
        expect(tokenLimit.isEmpty, "token limit chunk produces no token")
        expect(parser.reachedTokenLimit, "token limit state")
        expect(done.isEmpty, "done produces no token")
        expect(parser.isDone, "done state")

        let translationMessages = PromptBuilder.translationMessages(sourceText: "Good morning", targetLanguage: .simplifiedChinese)
        expect(translationMessages[0].content.contains("只输出原文读音、译文和译文读音"), "translation asks for source reading, text, and translation reading only")
        expect(translationMessages[1].content.contains("读音规则：中文用拼音；英文用 IPA 英标；日文用 ふりがな 和 ローマ字；其他语言用常用拉丁转写或 IPA。"), "reading guide rules")
        expect(translationMessages[1].content.contains("原文读音：<按识别出的源语言标注读音>"), "source reading output format")
        expect(translationMessages[1].content.contains("译文：<简体中文译文>"), "translation output format")
        expect(translationMessages[1].content.contains("译文读音：<拼音>"), "Chinese reading guide")
        expect(translationMessages[1].content.contains("Good morning"), "translation source included")
        expect(PromptBuilder.translationMessages(sourceText: "你好", targetLanguage: .english)[1].content.contains("译文读音：<IPA 英标>"), "English reading guide")
        expect(PromptBuilder.translationMessages(sourceText: "Hello", targetLanguage: .japanese)[1].content.contains("译文读音：<ふりがな；ローマ字>"), "Japanese reading guide")
        expect(TranslationContentPolicy.readingOptions(for: "Good morning") == .allEnabled, "short phrase enables reading")
        expect(TranslationContentPolicy.readingOptions(for: "as soon as possible") == .allEnabled, "short multi-word phrase enables reading")
        expect(TranslationContentPolicy.readingOptions(for: "早上好") == .allEnabled, "short CJK phrase enables reading")
        let longReadingOptions = TranslationContentPolicy.readingOptions(for: "The product team needs a clear threshold before rolling out the experiment.")
        expect(longReadingOptions.sourceEnabled == false, "sentence disables source reading")
        expect(longReadingOptions.translationEnabled == false, "sentence disables translation reading")
        expect(TranslationContentPolicy.shouldRequestKeywordExplanation(for: "") == false, "empty text skips keyword explanation")
        expect(TranslationContentPolicy.shouldRequestKeywordExplanation(for: "   ") == false, "blank text skips keyword explanation")
        expect(TranslationContentPolicy.shouldRequestKeywordExplanation(for: "threshold"), "single word requests keyword explanation")
        expect(TranslationContentPolicy.shouldRequestKeywordExplanation(for: "Good morning"), "short phrase requests keyword explanation")
        expect(TranslationContentPolicy.shouldRequestKeywordExplanation(for: "The product team needs a clear threshold before rolling out the experiment."), "sentence requests keyword explanation")
        expect(TranslationContentPolicy.shouldRequestKeywordExplanation(for: "这个实验需要一个明确阈值才能发布给所有用户。"), "CJK sentence requests keyword explanation")
        let sourceOnlyMessages = PromptBuilder.translationMessages(
            sourceText: "Good morning",
            targetLanguage: .simplifiedChinese,
            readingOptions: TranslationReadingOptions(sourceEnabled: true, translationEnabled: false)
        )
        expect(sourceOnlyMessages[1].content.contains("原文读音：<按识别出的源语言标注读音>"), "source-only reading includes source reading")
        expect(sourceOnlyMessages[1].content.contains("译文：<简体中文译文>"), "source-only reading includes translation")
        expect(sourceOnlyMessages[1].content.contains("译文读音：") == false, "source-only reading omits translation reading")
        let translationOnlyMessages = PromptBuilder.translationMessages(
            sourceText: "你好",
            targetLanguage: .english,
            readingOptions: TranslationReadingOptions(sourceEnabled: false, translationEnabled: true)
        )
        expect(translationOnlyMessages[1].content.contains("原文读音：") == false, "translation-only reading omits source reading")
        expect(translationOnlyMessages[1].content.contains("译文读音：<IPA 英标>"), "translation-only reading includes target reading")
        let noReadingMessages = PromptBuilder.translationMessages(
            sourceText: "Hello",
            targetLanguage: .japanese,
            readingOptions: TranslationReadingOptions(sourceEnabled: false, translationEnabled: false)
        )
        expect(noReadingMessages[1].content.contains("读音规则：") == false, "no reading omits reading rules")
        expect(noReadingMessages[1].content.contains("原文读音：") == false, "no reading omits source reading")
        expect(noReadingMessages[1].content.contains("译文：<日文译文>"), "no reading includes translation")
        expect(noReadingMessages[1].content.contains("译文读音：") == false, "no reading omits translation reading")

        let followUpMessages = PromptBuilder.followUpMessages(
            sourceText: "threshold",
            translation: "阈值",
            targetLanguage: .simplifiedChinese,
            history: [],
            question: "再给两个例句"
        )
        expect(followUpMessages[0].content.contains("所有追问默认针对原文"), "follow-up defaults to source text")
        expect(followUpMessages[0].content.contains("参考译文只作为理解辅助"), "translation is reference only")
        expect(followUpMessages[0].content.contains("明确要求优化译文或目标语言表达"), "target-language optimization is explicit")
        expect(followUpMessages[1].content.contains("原文：\nthreshold"), "source text included")
        expect(followUpMessages[1].content.contains("参考译文（简体中文）：\n阈值"), "reference translation included")
        expect(followUpMessages.last == ChatMessage(role: "user", content: "再给两个例句"), "free follow-up question preserved")
        expect(PromptBuilder.quickFollowUpQuestion(for: "解释用法", targetLanguage: .simplifiedChinese) == "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。", "explain usage targets source")
        expect(PromptBuilder.quickFollowUpQuestion(for: "给例句", targetLanguage: .simplifiedChinese) == "请针对原文中的核心表达给出 3 个例句，并附上简短说明。不要围绕参考译文造句。", "examples target source")
        expect(PromptBuilder.quickFollowUpQuestion(for: "更自然表达", targetLanguage: .simplifiedChinese) == "请基于原文和参考译文，给出更自然的简体中文表达。只输出改写后的简体中文译文；不要解释，不要分析原文。", "natural expression targets target language")
        expect(PromptBuilder.quickFollowUpQuestion(for: "语法分析", targetLanguage: .simplifiedChinese) == "请针对原文做语法分析，说明句子结构、关键成分和容易误解的点。不要分析参考译文，除非它影响理解。", "grammar targets source")
        expect(PromptBuilder.quickFollowUpQuestion(for: "这个译文自然吗", targetLanguage: .simplifiedChinese) == "这个译文自然吗", "custom translation question preserved")
        let keywordMessages = PromptBuilder.keywordExplanationMessages(
            sourceText: "The product team needs a clear threshold before rolling out the experiment.",
            translation: "产品团队需要一个明确的阈值，才能推出这个实验。",
            targetLanguage: .simplifiedChinese
        )
        expect(keywordMessages[0].content.contains("只针对原文解释关键词汇"), "keyword explanation targets source")
        expect(keywordMessages[0].content.contains("参考译文只作为理解辅助"), "keyword translation is reference")
        expect(keywordMessages[0].content.contains("只把“译文：”字段作为参考"), "keyword ignores reading fields")
        expect(keywordMessages[1].content.contains("尽量找出所有值得解释的关键词或短语"), "keyword coverage guidance")
        expect(keywordMessages[1].content.contains("由你根据原文复杂度决定解释数量"), "keyword count left to model")
        expect(keywordMessages[1].content.contains("原词/短语 — 含义 — 语境或用法 — 常见译法"), "keyword output format")
        expect(keywordMessages[1].content.contains("无需要特别解释的关键词汇"), "keyword fallback")
        expect(keywordMessages[1].content.contains("原文：\nThe product team needs a clear threshold before rolling out the experiment."), "keyword source included")
        expect(keywordMessages[1].content.contains("参考译文（简体中文）：\n产品团队需要一个明确的阈值，才能推出这个实验。"), "keyword translation included")
        let historyMessages = PromptBuilder.followUpMessages(
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
        expect(historyMessages.contains(ChatMessage(role: "user", content: "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。")), "history replays model question")
        expect(historyMessages.contains(ChatMessage(role: "user", content: "解释用法")) == false, "history omits display question")
        expect(historyMessages.contains(ChatMessage(role: "assistant", content: "表示触发某件事的界限。")), "history replays answer")

        expect(
            SelectionService.preferredAccessibilitySelection(
                markerText: "You have a new rate limit reset available\nYou were granted a rate limit reset.",
                rangeText: "range text",
                selectedText: "selected text"
            ) == "You have a new rate limit reset available\nYou were granted a rate limit reset.",
            "marker text preferred"
        )
        expect(
            SelectionService.preferredAccessibilitySelection(
                markerText: "  \n",
                rangeText: "unrelated range text",
                selectedText: "selected text"
            ) == "selected text",
            "selected text preferred over mismatched range text"
        )
        expect(
            SelectionService.preferredAccessibilitySelection(
                markerText: nil,
                rangeText: "You have a new rate limit reset available\nYou were granted a rate limit reset.",
                selectedText: "You have a new rate limit reset availableYou were granted a rate limit reset."
            ) == "You have a new rate limit reset available\nYou were granted a rate limit reset.",
            "range text restores dropped newline"
        )
        expect(
            SelectionService.preferredAccessibilitySelection(
                markerText: nil,
                rangeText: "",
                selectedText: "selected text"
            ) == "selected text",
            "selected text fallback"
        )
        expect(
            SelectionService.preferredAccessibilitySelection(
                markerText: nil,
                rangeText: " ",
                selectedText: "\n"
            ) == nil,
            "empty accessibility candidates"
        )

        let session = TranslationSession(sourceText: "Hello", targetLanguage: .simplifiedChinese)
        await MainActor.run {
            let debugProfile = LLMProfile(
                name: "本地 Ollama",
                baseURL: URL(string: "http://localhost:11434/v1/")!,
                apiKey: "secret-token",
                model: "gemma4:12b-mlx"
            )
            session.runTranslation(
                client: LLMClient(session: DirectCheckURLSession()),
                profile: debugProfile,
                streamingEnabled: true
            )
            expect(session.lastLLMContextSnapshot?.requestKind == .translation, "translation context snapshot kind")
            expect(session.lastLLMContextSnapshot?.messages == PromptBuilder.translationMessages(sourceText: "Hello", targetLanguage: .simplifiedChinese), "translation context messages")
            expect(session.lastLLMContextSnapshot?.jsonString().contains("secret-token") == false, "context JSON omits API key")
            expect(session.lastLLMContextSnapshot?.plainTextDescription().contains("Messages:") == true, "context text copy")
            session.translation = "你好"
            session.keywordExplanation = "Hello — 你好 — 问候语 — 你好"
            session.ask(
                question: PromptBuilder.quickFollowUpQuestion(for: "解释用法", targetLanguage: .simplifiedChinese),
                displayQuestion: "解释用法",
                client: LLMClient(session: DirectCheckURLSession()),
                profile: debugProfile,
                streamingEnabled: false
            )
            expect(session.lastLLMContextSnapshot?.requestKind == .followUp, "follow-up context snapshot kind")
            expect(session.lastLLMContextSnapshot?.messages.contains(ChatMessage(role: "user", content: "解释用法")) == false, "display question omitted from LLM messages")
            expect(session.lastLLMContextSnapshot?.messages.contains(ChatMessage(role: "assistant", content: "")) == false, "empty current assistant omitted from LLM messages")
            expect(session.lastLLMContextSnapshot?.messages.contains(ChatMessage(role: "user", content: "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。")) == true, "model question preserved")
            expect(session.followUps == [
                FollowUpTurn(
                    question: "解释用法",
                    llmQuestion: "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。",
                    answer: ""
                )
            ], "session stores display and model question")
        }
        for _ in 0..<20 {
            let hasAssistantResponse = await MainActor.run {
                session.lastLLMContextSnapshot?.messages.last == ChatMessage(role: "assistant", content: "回答")
            }
            if hasAssistantResponse {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        await MainActor.run {
            expect(session.lastLLMContextSnapshot?.messages.last == ChatMessage(role: "assistant", content: "回答"), "assistant response added to context snapshot")
            session.followUps = [FollowUpTurn(question: "解释用法", answer: "问候语")]
            session.close()
            expect(session.sourceText.isEmpty, "source cleared")
            expect(session.translation.isEmpty, "translation cleared")
            expect(session.keywordExplanation.isEmpty, "keyword explanation cleared")
            expect(session.followUps.isEmpty, "follow ups cleared")
            expect(session.lastLLMContextSnapshot == nil, "context snapshot cleared")
            expect(session.isClosed, "closed flag")
        }

        print("direct checks passed")
    }
}
SWIFT

swiftc "$ROOT_DIR"/Sources/GTransCore/*.swift "$HARNESS" -o "$BIN"
"$BIN"
