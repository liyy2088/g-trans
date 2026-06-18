import Foundation
import XCTest
@testable import GTransCore

final class LLMRequestBuilderTests: XCTestCase {
    func buildsOpenAICompatibleRequest() throws {
        let client = LLMClient()
        let profile = LLMProfile(
            name: "本地 Ollama",
            baseURL: URL(string: "http://localhost:11434/v1/")!,
            apiKey: "ollama",
            model: "gemma4:12b-mlx"
        )
        let request = try client.makeRequest(
            profile: profile,
            messages: [ChatMessage(role: "user", content: "Hi")],
            stream: true
        )

        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ollama")

        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)
        XCTAssertEqual(decoded.model, "gemma4:12b-mlx")
        XCTAssertTrue(decoded.stream)
        XCTAssertEqual(decoded.temperature, 0)
        XCTAssertEqual(decoded.maxTokens, LLMClient.maxOutputTokens)
        XCTAssertNil(decoded.maxCompletionTokens)
        XCTAssertEqual(decoded.reasoning, ReasoningConfig(effort: "none"))
        XCTAssertEqual(decoded.messages, [ChatMessage(role: "user", content: "Hi")])
    }

    func omitsReasoningForNonLocalEndpoint() throws {
        let client = LLMClient()
        let profile = LLMProfile(
            name: "OpenAI",
            baseURL: URL(string: "https://api.example.com/v1/")!,
            apiKey: "token",
            model: "example-model"
        )
        let request = try client.makeRequest(
            profile: profile,
            messages: [ChatMessage(role: "user", content: "Hi")],
            stream: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)
        XCTAssertNil(decoded.reasoning)
    }

    func buildsRequestsFromDifferentProfiles() throws {
        let client = LLMClient()
        let localProfile = LLMProfile(
            name: "本地",
            baseURL: URL(string: "http://localhost:11434/v1/")!,
            apiKey: "ollama",
            model: "local-model"
        )
        let remoteProfile = LLMProfile(
            name: "远端",
            baseURL: URL(string: "https://api.example.com/v1/")!,
            apiKey: "remote-token",
            model: "remote-model"
        )

        let localRequest = try client.makeRequest(profile: localProfile, messages: [], stream: false)
        let remoteRequest = try client.makeRequest(profile: remoteProfile, messages: [], stream: false)
        let localBody = try JSONDecoder().decode(ChatCompletionRequest.self, from: XCTUnwrap(localRequest.httpBody))
        let remoteBody = try JSONDecoder().decode(ChatCompletionRequest.self, from: XCTUnwrap(remoteRequest.httpBody))

        XCTAssertEqual(localRequest.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(localRequest.value(forHTTPHeaderField: "Authorization"), "Bearer ollama")
        XCTAssertEqual(localBody.model, "local-model")
        XCTAssertEqual(remoteRequest.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(remoteRequest.value(forHTTPHeaderField: "Authorization"), "Bearer remote-token")
        XCTAssertEqual(remoteBody.model, "remote-model")
    }

    func usesMaxCompletionTokensForReasoningModels() throws {
        let client = LLMClient()
        let profile = LLMProfile(
            name: "Reasoning model",
            baseURL: URL(string: "https://api.example.com/v1/")!,
            apiKey: "token",
            model: "gpt-5-example"
        )

        let request = try client.makeRequest(
            profile: profile,
            messages: [ChatMessage(role: "user", content: "Hi")],
            stream: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(decoded.model, "gpt-5-example")
        XCTAssertNil(decoded.maxTokens)
        XCTAssertEqual(decoded.maxCompletionTokens, LLMClient.maxOutputTokens)
    }

    func connectionTestUsesChatCompletionProbe() async throws {
        let session = CapturingURLSession()
        let client = LLMClient(session: session)
        let profile = LLMProfile(
            name: "Reasoning model",
            baseURL: URL(string: "https://api.example.com/v1/")!,
            apiKey: "token",
            model: "gpt-5-example"
        )

        try await client.testConnection(profile: profile)

        let request = try XCTUnwrap(session.lastRequest)
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(decoded.model, "gpt-5-example")
        XCTAssertEqual(decoded.maxCompletionTokens, 32)
        XCTAssertEqual(decoded.messages, [ChatMessage(role: "user", content: "ping")])
    }
}

private final class CapturingURLSession: URLSessionProtocol, @unchecked Sendable {
    private(set) var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8), response)
    }

    func lines(for request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
