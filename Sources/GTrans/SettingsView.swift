import GTransCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var baseURLText = ""
    @State private var selectedTab: SettingsTab = .llm
    @State private var showsAPIKey = false
    @State private var lastSavedConfiguration: AppConfiguration?

    private let preferenceControlColumnWidth: CGFloat = 220

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case permissions = "权限"
        case llm = "LLM 配置"
        case preferences = "偏好"
        case about = "关于"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tabPicker
            Divider()
            selectedTabContent
        }
        .padding(20)
        .frame(width: 860, height: 620)
        .onAppear {
            syncBaseURLText()
            lastSavedConfiguration = appState.configuration
            appState.refreshAccessibilityStatus()
        }
        .onChange(of: appState.configuration.selectedProfileID) { _ in
            syncBaseURLText()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            appState.refreshAccessibilityStatus()
        }
    }

    private var tabPicker: some View {
        HStack {
            Spacer()
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
            Spacer()
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .permissions:
            permissionsPage
        case .llm:
            llmPage
        case .preferences:
            preferencesPage
        case .about:
            aboutPage
        }
    }

    private var llmPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageDescription("管理翻译面板可用的模型服务。")
            llmProfileSection
            requestSettingsSection
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageDescription("G-Trans 需要辅助功能权限读取当前选中文本。")
            settingsGroup {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: appState.accessibilityEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(appState.accessibilityEnabled ? .green : .orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.accessibilityEnabled ? "辅助功能已开启" : "辅助功能未开启")
                            .font(.headline)
                        Text(appState.accessibilityEnabled ? "可以读取当前选中文本。" : "请在系统设置中为 G-Trans 开启辅助功能权限。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开系统设置") {
                        appState.openAccessibilitySettings()
                    }
                }
                if !appState.accessibilityEnabled {
                    Text("打开系统设置后，请在“隐私与安全性 > 辅助功能”中为 G-Trans 开启权限。如果系统设置中已开启但这里仍显示未开启，请删除 GTrans 后重新授权。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var preferencesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageDescription("设置默认语言、开机启动和快捷键。")
            settingsGroup {
                preferenceRow("默认目标语言") {
                    Picker("默认目标语言", selection: $appState.configuration.targetLanguage) {
                        ForEach(TargetLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150, alignment: .trailing)
                }
                preferenceRow("开机自动启动") {
                    Toggle("开机自动启动", isOn: $appState.configuration.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: appState.configuration.launchAtLogin) { enabled in
                            setLaunchAtLogin(enabled)
                        }
                }
                preferenceRow("快捷键") {
                    HStack(spacing: 10) {
                        Text("Option + Space")
                            .foregroundStyle(.secondary)
                        Button("更改...") {}
                            .disabled(true)
                    }
                }
            }
            Spacer()
            saveFooter
        }
    }

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageDescription("查看版本信息和诊断入口。")
            settingsGroup {
                preferenceRow("应用") {
                    Text("G-Trans")
                        .foregroundStyle(.secondary)
                }
                preferenceRow("诊断") {
                    Button("打开日志目录") {
                        appState.openLogDirectory()
                    }
                }
            }
            Spacer()
        }
    }

    private func pageDescription(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func preferenceRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.callout.weight(.medium))
            Spacer()
            HStack {
                Spacer(minLength: 0)
                content()
            }
            .frame(width: preferenceControlColumnWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private var requestSettingsSection: some View {
        settingsGroup {
            HStack(spacing: 18) {
                Text("请求设置")
                    .font(.callout.weight(.semibold))
                Spacer()
                Toggle("流式输出", isOn: $appState.configuration.streamingEnabled)
                    .toggleStyle(.switch)
            }
        }
    }

    private var llmProfileSection: some View {
        HStack(alignment: .top, spacing: 16) {
            profileList
                .frame(width: 270)
            Divider()
            profileEditor
        }
        .frame(maxHeight: .infinity)
    }

    private var profileList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("模型服务")
                .font(.headline)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(appState.configuration.profiles) { profile in
                        profileRow(profile)
                    }
                }
            }
            HStack(spacing: 8) {
                Button {
                    appState.addProfile()
                    lastSavedConfiguration = appState.configuration
                    syncBaseURLText()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 26, height: 24)
                }
                .help("新增配置")
                Button {
                    appState.deleteSelectedProfile()
                    lastSavedConfiguration = appState.configuration
                    syncBaseURLText()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 26, height: 24)
                }
                .disabled(appState.configuration.profiles.count <= 1)
                .help("删除当前配置")
                Spacer()
            }
        }
    }

    private func profileRow(_ profile: LLMProfile) -> some View {
        let isSelected = appState.configuration.selectedProfile?.id == profile.id
        let isCurrent = appState.configuration.selectedProfileID == profile.id
        return Button {
            commitBaseURLText()
            appState.selectProfile(id: profile.id)
            lastSavedConfiguration = appState.configuration
            syncBaseURLText()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(profile.isConfigured ? Color.blue : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(profile.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    if isCurrent {
                        Text("当前")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                Text(profileSubtitle(profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.38) : Color.secondary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func profileSubtitle(_ profile: LLMProfile) -> String {
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = profile.isConfigured ? "已配置" : "未完成"
        return "\(model.isEmpty ? "未填写模型名称" : model) · \(status)"
    }

    private var profileEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("配置详情")
                    .font(.headline)
                if let profile = appState.selectedProfile {
                    Text(profile.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            connectionStatusLine
            VStack(alignment: .leading, spacing: 10) {
                labeledTextField("名称", text: profileStringBinding(\.name))
                labeledTextField("服务地址", text: $baseURLText)
                    .onSubmit(commitBaseURLText)
                labeledAPIKeyField("API Key", text: profileStringBinding(\.apiKey))
                labeledTextField("模型名称", text: profileStringBinding(\.model))
            }
            HStack {
                Button("测试连接") {
                    commitBaseURLText()
                    appState.testSelectedProfileConnection()
                }
                connectionResultText
                Spacer()
                saveFooter
            }
            Spacer()
        }
    }

    private var connectionStatusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.selectedProfile?.isConfigured == true ? Color.blue : Color.orange)
                .frame(width: 7, height: 7)
            Text(appState.selectedProfile?.isConfigured == true ? "已配置" : "未完成")
                .font(.footnote.weight(.medium))
                .foregroundStyle(appState.selectedProfile?.isConfigured == true ? .blue : .orange)
            Text("当前用于翻译面板快速切换")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var connectionResultText: some View {
        if let message = appState.setupError {
            Label(connectionMessage(for: message), systemImage: connectionIcon(for: message))
                .font(.footnote)
                .foregroundStyle(connectionColor(for: message))
        }
    }

    private var saveFooter: some View {
        HStack(spacing: 10) {
            Text(hasUnsavedChanges ? "有未保存的更改" : "没有未保存的更改")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if hasUnsavedChanges {
                Button("保存配置") {
                    commitBaseURLText()
                    appState.saveSettings()
                    lastSavedConfiguration = appState.configuration
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("已保存") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        appState.configuration != lastSavedConfiguration || baseURLHasUnsavedChange
    }

    private var baseURLHasUnsavedChange: Bool {
        baseURLText.trimmingCharacters(in: .whitespacesAndNewlines) != (appState.selectedProfile?.baseURL.absoluteString ?? "")
    }

    private func labeledTextField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func labeledAPIKeyField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Group {
                    if showsAPIKey {
                        TextField(label, text: text)
                    } else {
                        SecureField(label, text: text)
                    }
                }
                .textFieldStyle(.roundedBorder)
                Button {
                    showsAPIKey.toggle()
                } label: {
                    Image(systemName: showsAPIKey ? "eye.slash" : "eye")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(showsAPIKey ? "隐藏 API Key" : "显示 API Key")
            }
            Text("已保存到钥匙串")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func profileStringBinding(_ keyPath: WritableKeyPath<LLMProfile, String>) -> Binding<String> {
        Binding(
            get: {
                appState.configuration.selectedProfile?[keyPath: keyPath] ?? ""
            },
            set: { value in
                appState.configuration.updateSelectedProfile { profile in
                    profile[keyPath: keyPath] = value
                }
            }
        )
    }

    private func syncBaseURLText() {
        baseURLText = appState.configuration.selectedProfile?.baseURL.absoluteString ?? ""
    }

    private func commitBaseURLText() {
        let trimmed = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            return
        }
        appState.configuration.updateSelectedProfile { profile in
            profile.baseURL = url
        }
    }

    private func connectionMessage(for message: String) -> String {
        switch message {
        case "连接测试通过。":
            return "连接成功，模型可用"
        case "正在测试连接...":
            return "正在测试连接..."
        default:
            return message
        }
    }

    private func connectionIcon(for message: String) -> String {
        switch message {
        case "连接测试通过。":
            return "checkmark.circle.fill"
        case "正在测试连接...":
            return "clock"
        default:
            return "exclamationmark.triangle.fill"
        }
    }

    private func connectionColor(for message: String) -> Color {
        switch message {
        case "连接测试通过。":
            return .green
        case "正在测试连接...":
            return .secondary
        default:
            return .orange
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            appState.setupError = "开机启动设置失败：\(error.localizedDescription)"
        }
        appState.saveSettings()
        lastSavedConfiguration = appState.configuration
    }
}
