import XCTest
@testable import GTransCore

final class StreamingChatParserTests: XCTestCase {
    func parsesContentChunksAndDone() throws {
        var parser = StreamingChatParser()
        let first = try parser.parse(line: #"data: {"choices":[{"delta":{"content":"你"}}]}"#)
        let second = try parser.parse(line: #"data: {"choices":[{"delta":{"content":"好"}}]}"#)
        let done = try parser.parse(line: "data: [DONE]")

        XCTAssertEqual(first, ["你"])
        XCTAssertEqual(second, ["好"])
        XCTAssertTrue(done.isEmpty)
        XCTAssertTrue(parser.isDone)
    }

    func detectsLengthFinishReason() throws {
        var parser = StreamingChatParser()
        let tokens = try parser.parse(line: #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#)

        XCTAssertTrue(tokens.isEmpty)
        XCTAssertTrue(parser.reachedTokenLimit)
    }

    func ignoresEmptyAndNonDataLines() throws {
        var parser = StreamingChatParser()
        XCTAssertTrue(try parser.parse(line: "").isEmpty)
        XCTAssertTrue(try parser.parse(line: "event: message").isEmpty)
    }

    func invalidJSONThrows() {
        var parser = StreamingChatParser()
        XCTAssertThrowsError(
            _ = try parser.parse(line: "data: {")
        )
    }
}
