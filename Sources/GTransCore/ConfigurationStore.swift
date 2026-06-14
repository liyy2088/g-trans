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
        static let targetLanguage = "targetLanguage"
        static let streamingEnabled = "streamingEnabled"
        static let launchAtLogin = "launchAtLogin"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppConfiguration {
        let baseURLString = defaults.string(forKey: Key.baseURL) ?? "https://api.openai.com/v1"
        let baseURL = URL(string: baseURLString) ?? URL(string: "https://api.openai.com/v1")!
        let model = defaults.string(forKey: Key.model) ?? ""
        let targetLanguage = TargetLanguage(rawValue: defaults.string(forKey: Key.targetLanguage) ?? "") ?? .simplifiedChinese
        let streamingEnabled = defaults.object(forKey: Key.streamingEnabled) as? Bool ?? true
        let launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        return AppConfiguration(
            baseURL: baseURL,
            model: model,
            targetLanguage: targetLanguage,
            streamingEnabled: streamingEnabled,
            launchAtLogin: launchAtLogin
        )
    }

    public func save(_ configuration: AppConfiguration) {
        defaults.set(configuration.baseURL.absoluteString, forKey: Key.baseURL)
        defaults.set(configuration.model, forKey: Key.model)
        defaults.set(configuration.targetLanguage.rawValue, forKey: Key.targetLanguage)
        defaults.set(configuration.streamingEnabled, forKey: Key.streamingEnabled)
        defaults.set(configuration.launchAtLogin, forKey: Key.launchAtLogin)
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
