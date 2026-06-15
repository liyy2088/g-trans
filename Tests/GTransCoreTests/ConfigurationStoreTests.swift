import Foundation
import XCTest
@testable import GTransCore

final class ConfigurationStoreTests: XCTestCase {
    func userDefaultsStoreRoundTripsConfigurationProfiles() {
        let suiteName = "GTransTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsConfigurationStore(defaults: defaults)
        let firstProfile = LLMProfile(
            id: "local",
            name: "本地 Ollama",
            baseURL: URL(string: "http://localhost:11434/v1/")!,
            apiKey: "ollama",
            model: "gemma4:12b-mlx"
        )
        let secondProfile = LLMProfile(
            id: "remote",
            name: "OpenAI",
            baseURL: URL(string: "https://api.example.com/v1/")!,
            apiKey: "token",
            model: "gpt-4.1-mini"
        )
        let config = AppConfiguration(
            targetLanguage: .english,
            streamingEnabled: false,
            launchAtLogin: true,
            selectedProfileID: secondProfile.id,
            profiles: [firstProfile, secondProfile]
        )

        store.save(config)

        XCTAssertEqual(store.load(), config)
    }

    func userDefaultsStoreMigratesLegacySingleConfiguration() {
        let suiteName = "GTransTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("http://localhost:11434/v1/", forKey: "baseURL")
        defaults.set("gemma4:12b-mlx", forKey: "model")
        defaults.set("ollama", forKey: "apiKey")
        let store = UserDefaultsConfigurationStore(defaults: defaults)

        let loaded = store.load()

        XCTAssertEqual(loaded.profiles.count, 1)
        XCTAssertEqual(loaded.selectedProfile?.name, "默认配置")
        XCTAssertEqual(loaded.selectedProfile?.baseURL.absoluteString, "http://localhost:11434/v1/")
        XCTAssertEqual(loaded.selectedProfile?.model, "gemma4:12b-mlx")
        XCTAssertEqual(loaded.selectedProfile?.apiKey, "ollama")
        XCTAssertTrue(loaded.isAPIConfigured)
    }

    func selectedProfileFallsBackToFirstProfile() {
        let firstProfile = LLMProfile(id: "local", name: "本地", apiKey: "ollama", model: "local-model")
        let secondProfile = LLMProfile(id: "remote", name: "远端", apiKey: "token", model: "remote-model")
        let config = AppConfiguration(
            selectedProfileID: "missing",
            profiles: [firstProfile, secondProfile]
        )

        XCTAssertEqual(config.selectedProfile, firstProfile)
    }

    func incompleteSelectedProfileIsNotConfigured() {
        let profile = LLMProfile(id: "local", name: "本地", apiKey: "", model: "local-model")
        let config = AppConfiguration(selectedProfileID: profile.id, profiles: [profile])

        XCTAssertFalse(config.isAPIConfigured)
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
