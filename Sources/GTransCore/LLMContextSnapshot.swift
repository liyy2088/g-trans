import Foundation

public enum LLMContextRequestKind: String, Codable, Equatable, Sendable {
    case translation
    case keywordExplanation
    case followUp

    public var displayName: String {
        switch self {
        case .translation:
            return "翻译"
        case .keywordExplanation:
            return "关键词汇"
        case .followUp:
            return "追问"
        }
    }
}

public struct LLMContextSessionSummary: Codable, Equatable, Sendable {
    public var sourceText: String
    public var translation: String
    public var keywordExplanation: String
    public var followUps: [FollowUpTurn]
    public var state: String

    public init(sourceText: String, translation: String, keywordExplanation: String, followUps: [FollowUpTurn], state: String) {
        self.sourceText = sourceText
        self.translation = translation
        self.keywordExplanation = keywordExplanation
        self.followUps = followUps
        self.state = state
    }
}

public struct LLMContextSnapshot: Codable, Equatable, Sendable {
    public var requestKind: LLMContextRequestKind
    public var createdAt: Date
    public var profileName: String
    public var baseURL: URL
    public var model: String
    public var streamingEnabled: Bool
    public var targetLanguage: TargetLanguage
    public var messages: [ChatMessage]
    public var sessionSummary: LLMContextSessionSummary

    public init(
        requestKind: LLMContextRequestKind,
        createdAt: Date = Date(),
        profileName: String,
        baseURL: URL,
        model: String,
        streamingEnabled: Bool,
        targetLanguage: TargetLanguage,
        messages: [ChatMessage],
        sessionSummary: LLMContextSessionSummary
    ) {
        self.requestKind = requestKind
        self.createdAt = createdAt
        self.profileName = profileName
        self.baseURL = baseURL
        self.model = model
        self.streamingEnabled = streamingEnabled
        self.targetLanguage = targetLanguage
        self.messages = messages
        self.sessionSummary = sessionSummary
    }

    public func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    public func plainTextDescription() -> String {
        var lines = [
            "请求类型：\(requestKind.displayName)",
            "配置：\(profileName)",
            "Base URL：\(baseURL.absoluteString)",
            "Model：\(model)",
            "Streaming：\(streamingEnabled ? "开启" : "关闭")",
            "目标语言：\(targetLanguage.displayName)",
            "创建时间：\(Self.dateFormatter.string(from: createdAt))",
            "",
            "Messages:"
        ]

        for (index, message) in messages.enumerated() {
            lines.append("")
            lines.append("[\(index + 1)] \(message.role)")
            lines.append(message.content)
        }

        return lines.joined(separator: "\n")
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
