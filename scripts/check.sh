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
        expect(followUpMessages[0].content.contains("译文只作为参考译文"), "translation is reference only")
        expect(followUpMessages[1].content.contains("原文：\nthreshold"), "source text included")
        expect(followUpMessages[1].content.contains("参考译文（简体中文）：\n阈值"), "reference translation included")
        expect(followUpMessages.last == ChatMessage(role: "user", content: "再给两个例句"), "free follow-up question preserved")
        expect(PromptBuilder.sourceFocusedFollowUpQuestion(for: "解释用法") == "请针对原文解释用法。", "explain usage targets source")
        expect(PromptBuilder.sourceFocusedFollowUpQuestion(for: "给例句") == "请针对原文给例句。", "examples target source")
        expect(PromptBuilder.sourceFocusedFollowUpQuestion(for: "更自然表达") == "请针对原文给出更自然的表达。", "natural expression targets source")
        expect(PromptBuilder.sourceFocusedFollowUpQuestion(for: "语法分析") == "请针对原文做语法分析。", "grammar targets source")
        expect(PromptBuilder.sourceFocusedFollowUpQuestion(for: "这个译文自然吗") == "这个译文自然吗", "custom translation question preserved")

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
                rangeText: "range text",
                selectedText: "selected text"
            ) == "range text",
            "range text fallback"
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
            session.translation = "你好"
            session.followUps = [FollowUpTurn(question: "解释用法", answer: "问候语")]
            session.close()
            expect(session.sourceText.isEmpty, "source cleared")
            expect(session.translation.isEmpty, "translation cleared")
            expect(session.followUps.isEmpty, "follow ups cleared")
            expect(session.isClosed, "closed flag")
        }

        print("direct checks passed")
    }
}
SWIFT

swiftc "$ROOT_DIR"/Sources/GTransCore/*.swift "$HARNESS" -o "$BIN"
"$BIN"
