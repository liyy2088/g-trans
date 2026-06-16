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
        expect(LanguageDirection.targetLanguage(for: "Hello world", defaultTarget: .english) == .simplifiedChinese, "English default should switch to Simplified Chinese for English source")

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
        expect(body.reasoning == ReasoningConfig(effort: "none"), "reasoning disabled")

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
