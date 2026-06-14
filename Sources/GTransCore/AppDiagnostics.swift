import Foundation
import OSLog

public enum AppDiagnostics {
    private static let store = DiagnosticsStore()

    public static var logDirectoryURL: URL {
        store.logDirectoryURL
    }

    public static var logFileURL: URL {
        store.logFileURL
    }

    public static func installCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            AppDiagnostics.error(
                "uncaught_exception",
                [
                    "name": exception.name.rawValue,
                    "reason": exception.reason ?? "",
                    "stack": exception.callStackSymbols.joined(separator: " | ")
                ]
            )
        }
    }

    public static func info(_ event: String, _ fields: [String: CustomStringConvertible] = [:]) {
        store.write(level: "info", event: event, fields: fields)
    }

    public static func error(_ event: String, _ fields: [String: CustomStringConvertible] = [:]) {
        store.write(level: "error", event: event, fields: fields)
    }
}

private final class DiagnosticsStore: @unchecked Sendable {
    let logDirectoryURL: URL
    let logFileURL: URL
    private let logger = Logger(subsystem: "local.g-trans.GTrans", category: "diagnostics")
    private let queue = DispatchQueue(label: "local.g-trans.diagnostics")
    private let maxLogBytes: UInt64 = 512 * 1024

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        logDirectoryURL = appSupport.appendingPathComponent("GTrans/Logs", isDirectory: true)
        logFileURL = logDirectoryURL.appendingPathComponent("gtrans.log")
        try? FileManager.default.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
    }

    func write(level: String, event: String, fields: [String: CustomStringConvertible]) {
        let sanitized = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(sanitize($0.value.description))" }
            .joined(separator: " ")
        let line = "\(Self.timestamp()) level=\(level) event=\(sanitize(event)) \(sanitized)\n"

        if level == "error" {
            logger.error("\(line, privacy: .public)")
        } else {
            logger.info("\(line, privacy: .public)")
        }

        queue.async { [logFileURL, logDirectoryURL, maxLogBytes] in
            try? FileManager.default.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
            rotateIfNeeded(logFileURL: logFileURL, maxLogBytes: maxLogBytes)
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFileURL.path),
                   let handle = try? FileHandle(forWritingTo: logFileURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? data.write(to: logFileURL)
                }
            }
        }
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

private func rotateIfNeeded(logFileURL: URL, maxLogBytes: UInt64) {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
          let size = attributes[.size] as? UInt64,
          size > maxLogBytes else {
        return
    }
    let rotatedURL = logFileURL.deletingLastPathComponent().appendingPathComponent("gtrans.previous.log")
    try? FileManager.default.removeItem(at: rotatedURL)
    try? FileManager.default.moveItem(at: logFileURL, to: rotatedURL)
}
