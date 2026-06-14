import Foundation
import XCTest
@testable import GTransCore

final class LLMRequestBuilderTests: XCTestCase {
    func buildsOpenAICompatibleRequest() throws {
        let client = LLMClient()
        let config = AppConfiguration(
            baseURL: URL(string: "http://localhost:11434/v1/")!,
            model: "gemma4:12b-mlx"
        )
        let request = try client.makeRequest(
            configuration: config,
            apiKey: "ollama",
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
        XCTAssertEqual(decoded.reasoning, ReasoningConfig(effort: "none"))
        XCTAssertEqual(decoded.messages, [ChatMessage(role: "user", content: "Hi")])
    }

    func omitsReasoningForNonLocalEndpoint() throws {
        let client = LLMClient()
        let config = AppConfiguration(
            baseURL: URL(string: "https://api.example.com/v1/")!,
            model: "example-model"
        )
        let request = try client.makeRequest(
            configuration: config,
            apiKey: "token",
            messages: [ChatMessage(role: "user", content: "Hi")],
            stream: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(ChatCompletionRequest.self, from: body)
        XCTAssertNil(decoded.reasoning)
    }
}
