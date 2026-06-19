import Foundation

public struct LLMProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var baseURL: URL
    public var apiKey: String
    public var model: String

    public init(
        id: String = UUID().uuidString,
        name: String = "默认配置",
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        apiKey: String = "",
        model: String = ""
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    public var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "未命名配置" : trimmedName
    }

    public var isConfigured: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct AppConfiguration: Equatable, Sendable {
    public var targetLanguage: TargetLanguage
    public var streamingEnabled: Bool
    public var sourceReadingEnabled: Bool
    public var translationReadingEnabled: Bool
    public var launchAtLogin: Bool
    public var selectedProfileID: String?
    public var profiles: [LLMProfile]

    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        model: String = "",
        apiKey: String = "",
        targetLanguage: TargetLanguage = .simplifiedChinese,
        streamingEnabled: Bool = true,
        sourceReadingEnabled: Bool = true,
        translationReadingEnabled: Bool = true,
        launchAtLogin: Bool = false,
        selectedProfileID: String? = nil,
        profiles: [LLMProfile]? = nil
    ) {
        self.targetLanguage = targetLanguage
        self.streamingEnabled = streamingEnabled
        self.sourceReadingEnabled = sourceReadingEnabled
        self.translationReadingEnabled = translationReadingEnabled
        self.launchAtLogin = launchAtLogin
        if let profiles {
            self.profiles = profiles.isEmpty ? [LLMProfile()] : profiles
            self.selectedProfileID = selectedProfileID ?? self.profiles.first?.id
        } else {
            let profile = LLMProfile(baseURL: baseURL, apiKey: apiKey, model: model)
            self.profiles = [profile]
            self.selectedProfileID = selectedProfileID ?? profile.id
        }
    }

    public var isAPIConfigured: Bool {
        selectedProfile?.isConfigured ?? false
    }

    public var selectedProfile: LLMProfile? {
        if let selectedProfileID,
           let profile = profiles.first(where: { $0.id == selectedProfileID }) {
            return profile
        }
        return profiles.first
    }

    public var selectedProfileIndex: Int? {
        guard let selectedProfile = selectedProfile else {
            return nil
        }
        return profiles.firstIndex(where: { $0.id == selectedProfile.id })
    }

    public var baseURL: URL {
        get { selectedProfile?.baseURL ?? URL(string: "https://api.openai.com/v1")! }
        set { updateSelectedProfile { $0.baseURL = newValue } }
    }

    public var model: String {
        get { selectedProfile?.model ?? "" }
        set { updateSelectedProfile { $0.model = newValue } }
    }

    public var apiKey: String {
        get { selectedProfile?.apiKey ?? "" }
        set { updateSelectedProfile { $0.apiKey = newValue } }
    }

    public mutating func updateSelectedProfile(_ update: (inout LLMProfile) -> Void) {
        ensureSelectedProfile()
        guard let index = selectedProfileIndex else {
            return
        }
        update(&profiles[index])
    }

    public mutating func ensureSelectedProfile() {
        if profiles.isEmpty {
            let profile = LLMProfile()
            profiles = [profile]
            selectedProfileID = profile.id
            return
        }
        if let selectedProfileID,
           profiles.contains(where: { $0.id == selectedProfileID }) {
            return
        }
        selectedProfileID = profiles.first?.id
    }
}

public struct TranslationReadingOptions: Equatable, Sendable {
    public var sourceEnabled: Bool
    public var translationEnabled: Bool

    public init(sourceEnabled: Bool = true, translationEnabled: Bool = true) {
        self.sourceEnabled = sourceEnabled
        self.translationEnabled = translationEnabled
    }

    public static let allEnabled = TranslationReadingOptions()
}

public enum TargetLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case traditionalChinese = "zh-Hant"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .simplifiedChinese:
            "简体中文"
        case .english:
            "英文"
        case .japanese:
            "日文"
        case .traditionalChinese:
            "繁体中文"
        }
    }
}
