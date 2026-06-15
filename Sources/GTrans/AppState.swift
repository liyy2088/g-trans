import AppKit
import Combine
import Foundation
import GTransCore

private enum AppStateError: Error {
    case selectionReadTimedOut
}

@MainActor
final class AppState: ObservableObject {
    @Published var configuration: AppConfiguration
    @Published var apiKey: String = ""
    @Published var setupError: String?
    @Published var copiedFeedback = false
    @Published var panelMessage: String?
    @Published private(set) var accessibilityEnabled = false

    let session = TranslationSession()
    private let configurationStore: ConfigurationStoring
    private let apiKeyStore: APIKeyStoring
    private let selectionService: SelectionService
    private let panelCoordinator: PanelCoordinator
    private let settingsPanelCoordinator: SettingsPanelCoordinator
    private let client: LLMClient
    private var hotkeyService: HotkeyService?
    private let statusBarController = StatusBarController()
    private var didPromptAccessibility = false
    private var cancellables: Set<AnyCancellable> = []

    init(
        configurationStore: ConfigurationStoring = UserDefaultsConfigurationStore(),
        apiKeyStore: APIKeyStoring = UserDefaultsAPIKeyStore(),
        selectionService: SelectionService = SelectionService(),
        panelCoordinator: PanelCoordinator? = nil,
        settingsPanelCoordinator: SettingsPanelCoordinator? = nil,
        client: LLMClient = LLMClient()
    ) {
        self.configurationStore = configurationStore
        self.apiKeyStore = apiKeyStore
        self.selectionService = selectionService
        self.panelCoordinator = panelCoordinator ?? PanelCoordinator()
        self.settingsPanelCoordinator = settingsPanelCoordinator ?? SettingsPanelCoordinator()
        self.client = client
        self.configuration = configurationStore.load()
        self.apiKey = (try? apiKeyStore.loadAPIKey()) ?? ""
        self.accessibilityEnabled = selectionService.accessibilityTrusted(prompt: false)
        AppDiagnostics.info(
            "app_state_init",
            [
                "base_url": configuration.baseURL.absoluteString,
                "model": configuration.model,
                "api_configured": isAPIConfigured,
                "accessibility": accessibilityEnabled
            ]
        )
        session.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var isAPIConfigured: Bool {
        configuration.isAPIConfigured && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start() {
        AppDiagnostics.info("app_start")
        statusBarController.install(appState: self)
        hotkeyService = HotkeyService { [weak self] in
            Task { @MainActor in
                await self?.handleTranslateShortcut()
            }
        }
        hotkeyService?.start()
        if let status = hotkeyService?.registrationStatus {
            UserDefaults.standard.set(Int(status), forKey: "hotkeyRegistrationStatus")
            AppDiagnostics.info("hotkey_registration", ["status": status])
        }
        if let status = hotkeyService?.registrationStatus, status != noErr {
            setupError = "快捷键注册失败：\(status)"
        }
        if !isAPIConfigured {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                openSettings()
            }
        }
        if let testText = launchTranslationText() {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                startTranslation(text: testText)
            }
        }
    }

    func saveSettings() {
        configurationStore.save(configuration)
        do {
            try apiKeyStore.saveAPIKey(apiKey)
            setupError = nil
            AppDiagnostics.info(
                "settings_saved",
                [
                    "base_url": configuration.baseURL.absoluteString,
                    "model": configuration.model,
                    "api_key_length": apiKey.count,
                    "streaming": configuration.streamingEnabled,
                    "target": configuration.targetLanguage.rawValue
                ]
            )
        } catch {
            setupError = "API Key 保存失败：\(error.localizedDescription)"
            AppDiagnostics.error("settings_save_failed", ["error": error.localizedDescription])
        }
    }

    func requestAccessibilityPermission() {
        AppDiagnostics.info("request_accessibility_permission")
        didPromptAccessibility = true
        _ = selectionService.accessibilityTrusted(prompt: true)
        refreshAccessibilityStatus()
    }

    func refreshAccessibilityStatus() {
        accessibilityEnabled = selectionService.accessibilityTrusted(prompt: false)
    }

    func openSettings() {
        AppDiagnostics.info("open_settings")
        settingsPanelCoordinator.show(appState: self)
    }

    func openLogDirectory() {
        AppDiagnostics.info("open_log_directory", ["path": AppDiagnostics.logDirectoryURL.path])
        NSWorkspace.shared.open(AppDiagnostics.logDirectoryURL)
    }

    func handleTranslateShortcut() async {
        AppDiagnostics.info("translate_shortcut")
        if panelCoordinator.isVisible {
            AppDiagnostics.info("translate_shortcut_replace_existing_panel")
        }
        guard isAPIConfigured else {
            AppDiagnostics.info("translate_shortcut_open_settings", ["reason": "api_not_configured"])
            openSettings()
            return
        }
        do {
            AppDiagnostics.info("selected_text_read_start")
            let text = try await readSelectedTextWithTimeout()
            panelMessage = nil
            AppDiagnostics.info("selected_text_read", ["length": text.count])
            startTranslation(text: text)
        } catch AppStateError.selectionReadTimedOut {
            panelMessage = "未读取到选中文本，请手动输入。"
            AppDiagnostics.error("selected_text_failed", ["reason": "timeout"])
            panelCoordinator.show(appState: self, mode: .manualInput)
        } catch SelectionError.accessibilityPermissionMissing {
            panelMessage = "需要开启辅助功能权限后才能读取选中文本。"
            AppDiagnostics.error("selected_text_failed", ["reason": "accessibility_permission_missing"])
            promptAccessibilityIfNeeded()
            panelCoordinator.show(appState: self, mode: .manualInput)
        } catch SelectionError.clipboardRestoreFailed {
            panelMessage = "未能恢复原剪贴板内容，请检查剪贴板。"
            AppDiagnostics.error("selected_text_failed", ["reason": "clipboard_restore_failed"])
            panelCoordinator.show(appState: self, mode: .manualInput)
        } catch {
            panelMessage = "未读取到选中文本，请手动输入。"
            AppDiagnostics.error("selected_text_failed", ["error": error.localizedDescription])
            panelCoordinator.show(appState: self, mode: .manualInput)
        }
    }

    private func promptAccessibilityIfNeeded() {
        guard !didPromptAccessibility else {
            return
        }
        requestAccessibilityPermission()
    }

    private func readSelectedTextWithTimeout() async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { @MainActor [selectionService] in
                try await selectionService.readSelectedText()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                throw AppStateError.selectionReadTimedOut
            }
            guard let result = try await group.next() else {
                throw AppStateError.selectionReadTimedOut
            }
            group.cancelAll()
            return result
        }
    }

    func openManualInput() {
        AppDiagnostics.info("open_manual_input")
        if isAPIConfigured {
            panelCoordinator.show(appState: self, mode: .manualInput)
            AppDiagnostics.info("open_manual_input_shown")
        } else {
            openSettings()
        }
    }

    func startTranslation(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            panelMessage = "请输入要翻译的文本。"
            AppDiagnostics.info("translation_rejected", ["reason": "empty_text"])
            panelCoordinator.show(appState: self, mode: .manualInput)
            return
        }
        panelMessage = nil
        let target = LanguageDirection.targetLanguage(for: trimmed, defaultTarget: configuration.targetLanguage)
        AppDiagnostics.info(
            "translation_start",
            [
                "source_length": trimmed.count,
                "target": target.rawValue,
                "model": configuration.model,
                "streaming": configuration.streamingEnabled
            ]
        )
        session.start(sourceText: trimmed, targetLanguage: target)
        panelCoordinator.show(appState: self, mode: .result)
        session.runTranslation(client: client, configuration: configuration, apiKey: apiKey)
    }

    private func launchTranslationText() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--translate-text"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    func regenerate() {
        AppDiagnostics.info("translation_regenerate", ["source_length": session.sourceText.count])
        session.runTranslation(client: client, configuration: configuration, apiKey: apiKey)
    }

    func startNewTranslationDraft() {
        AppDiagnostics.info("new_translation_draft")
        panelMessage = nil
        copiedFeedback = false
        session.close()
    }

    func ask(_ question: String, displayQuestion: String? = nil) {
        AppDiagnostics.info("follow_up_start", ["question_length": question.count])
        session.ask(question: question, displayQuestion: displayQuestion, client: client, configuration: configuration, apiKey: apiKey)
    }

    func closePanel() {
        AppDiagnostics.info("panel_close")
        session.close()
        panelCoordinator.close()
    }

    func requestClosePanel() {
        AppDiagnostics.info("panel_close_requested")
        DispatchQueue.main.async { [weak self] in
            self?.closePanel()
        }
    }

    func copyTranslation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.translation, forType: .string)
        AppDiagnostics.info("translation_copied", ["translation_length": session.translation.count])
        copiedFeedback = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copiedFeedback = false
        }
    }
}
