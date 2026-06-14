import Foundation

public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func lines(for request: URLRequest) -> AsyncThrowingStream<String, Error>
}

extension URLSession: URLSessionProtocol {
    public func lines(for request: URLRequest) -> AsyncThrowingStream<String, Error> {
        URLSessionLineStreamer(request: request).stream()
    }
}

private final class URLSessionLineStreamer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let request: URLRequest
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private var buffer = ""
    private var session: URLSession?

    init(request: URLRequest) {
        self.request = request
    }

    func stream() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.dataTask(with: request)
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.session?.invalidateAndCancel()
            }
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer += String(decoding: data, as: UTF8.self)
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            continuation?.yield(line)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.finish(throwing: error)
        } else {
            let tail = buffer.trimmingCharacters(in: .newlines)
            if !tail.isEmpty {
                continuation?.yield(tail)
            }
            continuation?.finish()
        }
        session.finishTasksAndInvalidate()
    }
}
