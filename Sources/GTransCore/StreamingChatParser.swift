import Foundation

public struct StreamingChatParser: Sendable {
    public private(set) var isDone = false

    public init() {}

    public mutating func parse(line: String) throws -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        guard trimmed.hasPrefix("data:") else {
            return []
        }

        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            isDone = true
            return []
        }

        let data = Data(payload.utf8)
        let decoded = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
        return decoded.choices.compactMap(\.delta.content)
    }
}

private struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            var content: String?
        }
        var delta: Delta
    }
    var choices: [Choice]
}
