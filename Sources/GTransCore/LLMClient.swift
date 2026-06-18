import Foundation

public struct ChatMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatCompletionRequest: Codable, Equatable, Sendable {
    public var model: String
    public var messages: [ChatMessage]
    public var temperature: Double
    public var tokenLimit: OutputTokenLimit?
    public var reasoning: ReasoningConfig?
    public var stream: Bool

    public var maxTokens: Int? {
        guard case .maxTokens(let value) = tokenLimit else {
            return nil
        }
        return value
    }

    public var maxCompletionTokens: Int? {
        guard case .maxCompletionTokens(let value) = tokenLimit else {
            return nil
        }
        return value
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case reasoning
        case stream
    }

    public init(
        model: String,
        messages: [ChatMessage],
        temperature: Double,
        tokenLimit: OutputTokenLimit?,
        reasoning: ReasoningConfig?,
        stream: Bool
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.tokenLimit = tokenLimit
        self.reasoning = reasoning
        self.stream = stream
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        temperature = try container.decode(Double.self, forKey: .temperature)
        let maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
        let maxCompletionTokens = try container.decodeIfPresent(Int.self, forKey: .maxCompletionTokens)
        if let maxCompletionTokens {
            tokenLimit = .maxCompletionTokens(maxCompletionTokens)
        } else if let maxTokens {
            tokenLimit = .maxTokens(maxTokens)
        } else {
            tokenLimit = nil
        }
        reasoning = try container.decodeIfPresent(ReasoningConfig.self, forKey: .reasoning)
        stream = try container.decode(Bool.self, forKey: .stream)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(temperature, forKey: .temperature)
        switch tokenLimit {
        case .maxTokens(let value):
            try container.encode(value, forKey: .maxTokens)
        case .maxCompletionTokens(let value):
            try container.encode(value, forKey: .maxCompletionTokens)
        case nil:
            break
        }
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encode(stream, forKey: .stream)
    }
}

public enum OutputTokenLimit: Equatable, Sendable {
    case maxTokens(Int)
    case maxCompletionTokens(Int)
}

public struct ReasoningConfig: Codable, Equatable, Sendable {
    public var effort: String

    public init(effort: String) {
        self.effort = effort
    }
}

public enum LLMClientError: Error, Equatable {
    case invalidBaseURL
    case unauthorized
    case modelNotFound
    case rateLimited
    case serverError(Int)
    case badStatus(Int, String)
    case emptyResponse
}

public struct LLMClient: Sendable {
    public static let maxOutputTokens = 2048
    public static let tokenLimitMessage = "\n\n（输出达到 token 上限，可能未完成。请重新生成或继续追问。）"

    private let session: URLSessionProtocol

    public init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    public func makeRequest(
        profile: LLMProfile,
        messages: [ChatMessage],
        stream: Bool
    ) throws -> URLRequest {
        try makeRequest(
            profile: profile,
            messages: messages,
            stream: stream,
            maxOutputTokens: Self.maxOutputTokens
        )
    }

    private func makeRequest(
        profile: LLMProfile,
        messages: [ChatMessage],
        stream: Bool,
        maxOutputTokens: Int
    ) throws -> URLRequest {
        guard let url = URL(string: "chat/completions", relativeTo: normalizedBaseURL(profile.baseURL))?.absoluteURL else {
            throw LLMClientError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(profile.apiKey)", forHTTPHeaderField: "Authorization")
        let body = ChatCompletionRequest(
            model: profile.model,
            messages: messages,
            temperature: 0,
            tokenLimit: outputTokenLimit(for: profile.model, maxOutputTokens: maxOutputTokens),
            reasoning: reasoningConfig(for: profile.baseURL),
            stream: stream
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public func complete(
        profile: LLMProfile,
        streamingEnabled: Bool,
        messages: [ChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        if streamingEnabled {
            do {
                return try await stream(profile: profile, messages: messages)
            } catch {
                return try await completeOnce(profile: profile, messages: messages)
            }
        }
        return try await completeOnce(profile: profile, messages: messages)
    }

    public func stream(
        profile: LLMProfile,
        messages: [ChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        let request = try makeRequest(profile: profile, messages: messages, stream: true)
        let lines = session.lines(for: request)

        return AsyncThrowingStream { continuation in
            Task {
                var parser = StreamingChatParser()
                var didReportTokenLimit = false
                do {
                    for try await line in lines {
                        for token in try parser.parse(line: line) {
                            continuation.yield(token)
                        }
                        if parser.reachedTokenLimit, !didReportTokenLimit {
                            continuation.yield(Self.tokenLimitMessage)
                            didReportTokenLimit = true
                        }
                        if parser.isDone {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func completeOnce(
        profile: LLMProfile,
        messages: [ChatMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        let request = try makeRequest(profile: profile, messages: messages, stream: false)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let choice = decoded.choices.first,
              let content = choice.message?.displayContent,
              !content.isEmpty else {
            throw LLMClientError.emptyResponse
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(content)
            if choice.finishReason == "length" {
                continuation.yield(Self.tokenLimitMessage)
            }
            continuation.finish()
        }
    }

    public func testConnection(profile: LLMProfile) async throws {
        var request = try makeRequest(
            profile: profile,
            messages: [ChatMessage(role: "user", content: "ping")],
            stream: false,
            maxOutputTokens: 32
        )
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    public func makeRequest(
        configuration: AppConfiguration,
        apiKey: String,
        messages: [ChatMessage],
        stream: Bool
    ) throws -> URLRequest {
        var profile = configuration.selectedProfile ?? LLMProfile()
        if profile.apiKey.isEmpty {
            profile.apiKey = apiKey
        }
        return try makeRequest(profile: profile, messages: messages, stream: stream)
    }

    private func normalizedBaseURL(_ baseURL: URL) -> URL {
        var string = baseURL.absoluteString
        if !string.hasSuffix("/") {
            string += "/"
        }
        return URL(string: string)!
    }

    private func outputTokenLimit(for model: String, maxOutputTokens: Int) -> OutputTokenLimit {
        if shouldUseMaxCompletionTokens(for: model) {
            return .maxCompletionTokens(maxOutputTokens)
        }
        return .maxTokens(maxOutputTokens)
    }

    private func shouldUseMaxCompletionTokens(for model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("gpt-5") ||
            normalized.hasPrefix("o1") ||
            normalized.hasPrefix("o3") ||
            normalized.hasPrefix("o4")
    }

    private func reasoningConfig(for baseURL: URL) -> ReasoningConfig? {
        guard let host = baseURL.host?.lowercased(),
              host == "localhost" || host == "127.0.0.1" else {
            return nil
        }
        return ReasoningConfig(effort: "none")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            return
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw LLMClientError.unauthorized
        case 404:
            let body = String(decoding: data, as: UTF8.self)
            throw LLMClientError.badStatus(http.statusCode, body)
        case 429:
            throw LLMClientError.rateLimited
        case 500..<600:
            throw LLMClientError.serverError(http.statusCode)
        default:
            let body = String(decoding: data, as: UTF8.self)
            throw LLMClientError.badStatus(http.statusCode, body)
        }
    }
}

public enum LLMErrorPresenter {
    public static func message(for error: Error) -> String {
        if let llmError = error as? LLMClientError {
            switch llmError {
            case .invalidBaseURL:
                return "base_url 无效，请检查设置。"
            case .unauthorized:
                return "API Key 或权限错误，请打开设置检查。"
            case .modelNotFound:
                return "模型名或 base_url 可能错误。"
            case .rateLimited:
                return "请求被限流，请稍后重试。"
            case .serverError:
                return "服务端暂时不可用，已停止重试。"
            case .badStatus(let status, let body):
                if status == 404, body.contains("DeploymentNotFound") {
                    return "模型或 deployment 不存在，请检查模型名称。"
                }
                return "请求失败（HTTP \(status)）。"
            case .emptyResponse:
                return "模型没有返回内容。"
            }
        }
        return "网络或服务错误：\(error.localizedDescription)"
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String
            var reasoning: String?

            var displayContent: String {
                let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedContent.isEmpty {
                    return trimmedContent
                }
                return reasoning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
        }
        var message: Message?
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    var choices: [Choice]
}
