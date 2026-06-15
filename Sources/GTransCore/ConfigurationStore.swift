import Foundation

public protocol APIKeyStoring: Sendable {
    func loadAPIKey() throws -> String
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey() throws
}

public protocol ConfigurationStoring: Sendable {
    func load() -> AppConfiguration
    func save(_ configuration: AppConfiguration)
}

public final class UserDefaultsConfigurationStore: ConfigurationStoring, @unchecked Sendable {
    private enum Key {
        static let baseURL = "baseURL"
        static let model = "model"
        static let apiKey = "apiKey"
        static let targetLanguage = "targetLanguage"
        static let streamingEnabled = "streamingEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let profiles = "llmProfiles"
        static let selectedProfileID = "selectedProfileID"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppConfiguration {
        let targetLanguage = TargetLanguage(rawValue: defaults.string(forKey: Key.targetLanguage) ?? "") ?? .simplifiedChinese
        let streamingEnabled = defaults.object(forKey: Key.streamingEnabled) as? Bool ?? true
        let launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        let profiles = loadProfiles()
        let selectedProfileID = defaults.string(forKey: Key.selectedProfileID)
        return AppConfiguration(
            targetLanguage: targetLanguage,
            streamingEnabled: streamingEnabled,
            launchAtLogin: launchAtLogin,
            selectedProfileID: selectedProfileID,
            profiles: profiles
        )
    }

    public func save(_ configuration: AppConfiguration) {
        if let data = try? JSONEncoder().encode(configuration.profiles) {
            defaults.set(data, forKey: Key.profiles)
        }
        defaults.set(configuration.selectedProfile?.id, forKey: Key.selectedProfileID)
        defaults.set(configuration.targetLanguage.rawValue, forKey: Key.targetLanguage)
        defaults.set(configuration.streamingEnabled, forKey: Key.streamingEnabled)
        defaults.set(configuration.launchAtLogin, forKey: Key.launchAtLogin)
    }

    private func loadProfiles() -> [LLMProfile] {
        if let data = defaults.data(forKey: Key.profiles),
           let profiles = try? JSONDecoder().decode([LLMProfile].self, from: data),
           !profiles.isEmpty {
            return profiles
        }

        let baseURLString = defaults.string(forKey: Key.baseURL) ?? "https://api.openai.com/v1"
        let baseURL = URL(string: baseURLString) ?? URL(string: "https://api.openai.com/v1")!
        return [
            LLMProfile(
                name: "默认配置",
                baseURL: baseURL,
                apiKey: defaults.string(forKey: Key.apiKey) ?? "",
                model: defaults.string(forKey: Key.model) ?? ""
            )
        ]
    }
}

public final class UserDefaultsAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private enum Key {
        static let apiKey = "apiKey"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadAPIKey() throws -> String {
        defaults.string(forKey: Key.apiKey) ?? ""
    }

    public func saveAPIKey(_ apiKey: String) throws {
        defaults.set(apiKey, forKey: Key.apiKey)
    }

    public func deleteAPIKey() throws {
        defaults.removeObject(forKey: Key.apiKey)
    }
}
