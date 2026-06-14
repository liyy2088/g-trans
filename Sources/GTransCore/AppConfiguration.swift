import Foundation

public struct AppConfiguration: Equatable, Sendable {
    public var baseURL: URL
    public var model: String
    public var targetLanguage: TargetLanguage
    public var streamingEnabled: Bool
    public var launchAtLogin: Bool

    public init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        model: String = "",
        targetLanguage: TargetLanguage = .simplifiedChinese,
        streamingEnabled: Bool = true,
        launchAtLogin: Bool = false
    ) {
        self.baseURL = baseURL
        self.model = model
        self.targetLanguage = targetLanguage
        self.streamingEnabled = streamingEnabled
        self.launchAtLogin = launchAtLogin
    }

    public var isAPIConfigured: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum TargetLanguage: String, CaseIterable, Identifiable, Sendable {
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
