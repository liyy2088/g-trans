import Foundation

public enum PromptBuilder {
    public static func sourceFocusedFollowUpQuestion(for title: String) -> String {
        switch title {
        case "解释用法":
            "请针对原文解释用法。"
        case "给例句":
            "请针对原文给例句。"
        case "更自然表达":
            "请针对原文给出更自然的表达。"
        case "语法分析":
            "请针对原文做语法分析。"
        default:
            title
        }
    }

    public static func translationMessages(sourceText: String, targetLanguage: TargetLanguage) -> [ChatMessage] {
        [
            ChatMessage(role: "system", content: "你是一个专业翻译引擎。只输出译文，不解释，不加引号。"),
            ChatMessage(role: "user", content: "请自动识别源语言，并翻译为\(targetLanguage.displayName)：\n\n\(sourceText)")
        ]
    }

    public static func followUpMessages(
        sourceText: String,
        translation: String,
        targetLanguage: TargetLanguage,
        history: [FollowUpTurn],
        question: String
    ) -> [ChatMessage] {
        var messages = [
            ChatMessage(role: "system", content: "你是一个翻译助手。回答要简洁。所有追问默认针对原文；译文只作为参考译文。只有用户明确询问译文、翻译结果或目标语言表达时，才分析译文。"),
            ChatMessage(
                role: "user",
                content: """
                原文：
                \(sourceText)

                参考译文（\(targetLanguage.displayName)）：
                \(translation)
                """
            )
        ]
        for turn in history.suffix(4) {
            messages.append(ChatMessage(role: "user", content: turn.question))
            messages.append(ChatMessage(role: "assistant", content: turn.answer))
        }
        messages.append(ChatMessage(role: "user", content: question))
        return messages
    }
}
