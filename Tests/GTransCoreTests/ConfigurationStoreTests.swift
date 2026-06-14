import Foundation
import XCTest
@testable import GTransCore

final class ConfigurationStoreTests: XCTestCase {
    func userDefaultsStoreRoundTripsNonSecretConfiguration() {
        let suiteName = "GTransTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsConfigurationStore(defaults: defaults)
        let config = AppConfiguration(
            baseURL: URL(string: "http://localhost:11434/v1/")!,
            model: "gemma4:12b-mlx",
            targetLanguage: .english,
            streamingEnabled: false,
            launchAtLogin: true
        )

        store.save(config)

        XCTAssertEqual(store.load(), config)
    }

    func testUserDefaultsAPIKeyStoreRoundTripsAPIKey() throws {
        let suiteName = "GTransTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAPIKeyStore(defaults: defaults)

        try store.saveAPIKey("ollama")

        XCTAssertEqual(try store.loadAPIKey(), "ollama")
        try store.deleteAPIKey()
        XCTAssertEqual(try store.loadAPIKey(), "")
    }
}
