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
    @Published var setupError: String?
    @Published var copiedTranslationFeedback = false
    @Published var copiedSourceFeedback = false
    @Published var panelMessage: String?
    @Published private(set) var accessibilityEnabled = false

    let session = TranslationSession()
    private let configurationStore: ConfigurationStoring
    private let selectionService: SelectionService
    private let panelCoordinator: PanelCoordinator
    private let settingsPanelCoordinator: SettingsPanelCoordinator
    private let client: LLMClient
    private var hotkeyService: HotkeyService?
    private let statusBarController = StatusBarController()
    private var didPromptAccessibility = false
    private var lastExternalApplication: NSRunningApplication?
    private var cancellables: Set<AnyCancellable> = []

    init(
        configurationStore: ConfigurationStoring = UserDefaultsConfigurationStore(),
        selectionService: SelectionService = SelectionService(),
        panelCoordinator: PanelCoordinator? = nil,
        settingsPanelCoordinator: SettingsPanelCoordinator? = nil,
        client: LLMClient = LLMClient()
    ) {
        self.configurationStore = configurationStore
        self.selectionService = selectionService
        self.panelCoordinator = panelCoordinator ?? PanelCoordinator()
        self.settingsPanelCoordinator = settingsPanelCoordinator ?? SettingsPanelCoordinator()
        self.client = client
        self.configuration = configurationStore.load()
        self.configuration.ensureSelectedProfile()
        self.accessibilityEnabled = selectionService.accessibilityTrusted(prompt: false)
        AppDiagnostics.info(
            "app_state_init",
            [
                "base_url": configuration.baseURL.absoluteString,
                "model": configuration.model,
                "profile_name": selectedProfile?.displayName ?? "",
                "api_configured": isAPIConfigured,
                "accessibility": accessibilityEnabled
            ]
        )
        session.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        observeActiveApplications()
    }

    var isAPIConfigured: Bool {
        configuration.isAPIConfigured
    }

    var selectedProfile: LLMProfile? {
        configuration.selectedProfile
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
        configuration.ensureSelectedProfile()
        configurationStore.save(configuration)
        setupError = nil
        AppDiagnostics.info(
            "settings_saved",
            [
                "profile_name": selectedProfile?.displayName ?? "",
                "base_url": configuration.baseURL.absoluteString,
                "model": configuration.model,
                "api_key_length": configuration.apiKey.count,
                "profile_count": configuration.profiles.count,
                "streaming": configuration.streamingEnabled,
                "target": configuration.targetLanguage.rawValue
            ]
        )
    }

    func selectProfile(id: String) {
        guard configuration.profiles.contains(where: { $0.id == id }) else {
            return
        }
        configuration.selectedProfileID = id
        saveSettings()
    }

    func addProfile() {
        let profile = LLMProfile(name: "新配置")
        configuration.profiles.append(profile)
        configuration.selectedProfileID = profile.id
        saveSettings()
    }

    func deleteSelectedProfile() {
        guard configuration.profiles.count > 1,
              let selectedProfileID = configuration.selectedProfile?.id else {
            return
        }
        configuration.profiles.removeAll { $0.id == selectedProfileID }
        configuration.selectedProfileID = configuration.profiles.first?.id
        saveSettings()
    }

    func testSelectedProfileConnection() {
        guard let profile = selectedProfile else {
            setupError = "没有可测试的 LLM 配置。"
            return
        }
        guard profile.isConfigured else {
            setupError = "请先填写 API Key 和 model。"
            return
        }
        setupError = "正在测试连接..."
        Task {
            do {
                try await client.testConnection(profile: profile)
                await MainActor.run {
                    setupError = "连接测试通过。"
                }
            } catch {
                await MainActor.run {
                    setupError = LLMErrorPresenter.message(for: error)
                }
            }
        }
    }

    func requestAccessibilityPermission() {
        AppDiagnostics.info("request_accessibility_permission")
        didPromptAccessibility = true
        _ = selectionService.accessibilityTrusted(prompt: true)
        refreshAccessibilityStatus()
    }

    func openAccessibilitySettings() {
        AppDiagnostics.info("open_accessibility_settings")
        requestAccessibilityPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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
        let selectionSourceApplication = lastExternalApplication
        if panelCoordinator.isVisible {
            AppDiagnostics.info("translate_shortcut_existing_panel_visible")
        }
        guard isAPIConfigured else {
            AppDiagnostics.info("translate_shortcut_open_settings", ["reason": "api_not_configured"])
            openSettings()
            return
        }
        do {
            AppDiagnostics.info(
                "selected_text_read_start",
                [
                    "source_bundle": selectionSourceApplication?.bundleIdentifier ?? "",
                    "source_name": selectionSourceApplication?.localizedName ?? ""
                ]
            )
            let text = try await readSelectedTextWithTimeout(in: selectionSourceApplication) {
                if self.panelCoordinator.focusExistingPanel() {
                    AppDiagnostics.info("translate_shortcut_focus_existing_panel_while_reading_selection")
                }
            }
            panelMessage = nil
            AppDiagnostics.info("selected_text_read", ["length": text.count])
            startTranslation(text: text)
        } catch AppStateError.selectionReadTimedOut {
            AppDiagnostics.error("selected_text_failed", ["reason": "timeout"])
            focusExistingPanelOrShowManualInput(message: "未读取到选中文本，请手动输入。")
        } catch SelectionError.accessibilityPermissionMissing {
            AppDiagnostics.error("selected_text_failed", ["reason": "accessibility_permission_missing"])
            promptAccessibilityIfNeeded()
            focusExistingPanelOrShowManualInput(message: "需要开启辅助功能权限后才能读取选中文本。")
        } catch SelectionError.clipboardRestoreFailed {
            AppDiagnostics.error("selected_text_failed", ["reason": "clipboard_restore_failed"])
            focusExistingPanelOrShowManualInput(message: "未能恢复原剪贴板内容，请检查剪贴板。")
        } catch {
            AppDiagnostics.error("selected_text_failed", ["error": error.localizedDescription])
            focusExistingPanelOrShowManualInput(message: "未读取到选中文本，请手动输入。")
        }
    }

    private func promptAccessibilityIfNeeded() {
        guard !didPromptAccessibility else {
            return
        }
        requestAccessibilityPermission()
    }

    private func observeActiveApplications() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] app in
                self?.rememberExternalApplication(app)
            }
            .store(in: &cancellables)
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        lastExternalApplication = application
    }

    private func readSelectedTextWithTimeout(
        in application: NSRunningApplication?,
        afterClipboardFallbackPosted: @escaping @MainActor () -> Void = {}
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { @MainActor [selectionService] in
                try await selectionService.readSelectedText(
                    in: application,
                    afterClipboardFallbackPosted: afterClipboardFallbackPosted
                )
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

    func openCurrentTranslationWindow() {
        AppDiagnostics.info("open_current_translation_window")
        if panelCoordinator.focusExistingPanel() {
            AppDiagnostics.info("open_current_translation_window_focus_existing")
            return
        }
        AppDiagnostics.info("open_current_translation_window_open_manual_input")
        openManualInput()
    }

    private func focusExistingPanelOrShowManualInput(message: String) {
        if panelCoordinator.focusExistingPanel() {
            AppDiagnostics.info("translate_shortcut_focus_existing_panel")
            return
        }
        panelMessage = message
        AppDiagnostics.info("translate_shortcut_open_manual_input", ["reason": "selection_unavailable"])
        panelCoordinator.show(appState: self, mode: .manualInput)
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
        copiedTranslationFeedback = false
        copiedSourceFeedback = false
        let target = LanguageDirection.targetLanguage(for: trimmed, defaultTarget: configuration.targetLanguage)
        AppDiagnostics.info(
            "translation_start",
            [
                "source_length": trimmed.count,
                "target": target.rawValue,
                "profile_name": selectedProfile?.displayName ?? "",
                "base_url": configuration.baseURL.absoluteString,
                "model": configuration.model,
                "streaming": configuration.streamingEnabled,
                "reading_auto_enabled": TranslationContentPolicy.readingOptions(for: trimmed) == .allEnabled,
                "keyword_auto_enabled": TranslationContentPolicy.shouldRequestKeywordExplanation(for: trimmed)
            ]
        )
        session.start(sourceText: trimmed, targetLanguage: target)
        panelCoordinator.show(appState: self, mode: .result)
        guard let profile = selectedProfile else {
            openSettings()
            return
        }
        session.runTranslation(
            client: client,
            profile: profile,
            streamingEnabled: configuration.streamingEnabled,
            readingOptions: translationReadingOptions
        )
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
        copiedTranslationFeedback = false
        copiedSourceFeedback = false
        guard let profile = selectedProfile else {
            openSettings()
            return
        }
        session.runTranslation(
            client: client,
            profile: profile,
            streamingEnabled: configuration.streamingEnabled,
            readingOptions: translationReadingOptions
        )
    }

    func startNewTranslationDraft() {
        AppDiagnostics.info("new_translation_draft")
        panelMessage = nil
        copiedTranslationFeedback = false
        copiedSourceFeedback = false
        session.close()
    }

    func ask(_ question: String, displayQuestion: String? = nil) {
        AppDiagnostics.info("follow_up_start", ["question_length": question.count])
        guard let profile = selectedProfile else {
            openSettings()
            return
        }
        session.ask(question: question, displayQuestion: displayQuestion, client: client, profile: profile, streamingEnabled: configuration.streamingEnabled)
    }

    private var translationReadingOptions: TranslationReadingOptions {
        TranslationContentPolicy.readingOptions(for: session.sourceText)
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
        copiedTranslationFeedback = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copiedTranslationFeedback = false
        }
    }

    func copySourceText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.sourceText, forType: .string)
        AppDiagnostics.info("source_copied", ["source_length": session.sourceText.count])
        copiedSourceFeedback = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copiedSourceFeedback = false
        }
    }
}
