import Foundation

public enum PromptBuilder {
    public static func quickFollowUpQuestion(for title: String, targetLanguage: TargetLanguage) -> String {
        switch title {
        case "解释用法":
            "请针对原文解释这个表达的含义、常见用法和适用语境。不要分析参考译文，除非它影响理解。"
        case "给例句":
            "请针对原文中的核心表达给出 3 个例句，并附上简短说明。不要围绕参考译文造句。"
        case "更自然表达":
            "请基于原文和参考译文，给出更自然的\(targetLanguage.displayName)表达。只输出改写后的\(targetLanguage.displayName)译文；不要解释，不要分析原文。"
        case "语法分析":
            "请针对原文做语法分析，说明句子结构、关键成分和容易误解的点。不要分析参考译文，除非它影响理解。"
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
            ChatMessage(role: "system", content: "你是一个翻译助手。回答要简洁。除非用户明确要求优化译文或目标语言表达，所有追问默认针对原文；参考译文只作为理解辅助。遇到“更自然表达”时，应基于原文和参考译文输出更自然的目标语言译法。"),
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
            messages.append(ChatMessage(role: "user", content: turn.modelQuestion))
            messages.append(ChatMessage(role: "assistant", content: turn.answer))
        }
        messages.append(ChatMessage(role: "user", content: question))
        return messages
    }
}
