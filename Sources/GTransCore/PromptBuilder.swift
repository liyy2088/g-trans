import Foundation

public enum PromptBuilder {
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
            ChatMessage(role: "system", content: "你是一个翻译助手。回答要简洁，围绕本次翻译上下文。"),
            ChatMessage(
                role: "user",
                content: """
                原文：
                \(sourceText)

                译文（\(targetLanguage.displayName)）：
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
