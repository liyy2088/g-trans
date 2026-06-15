import GTransCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var baseURLText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            permissionSection
            llmProfileSection
            preferenceSection
        }
        .padding(20)
        .frame(width: 860, height: 620)
        .onAppear {
            syncBaseURLText()
            appState.refreshAccessibilityStatus()
        }
        .onChange(of: appState.configuration.selectedProfileID) { _ in
            syncBaseURLText()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            appState.refreshAccessibilityStatus()
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("权限")
                    .font(.headline)
                Spacer()
                Text(appState.accessibilityEnabled ? "辅助功能已开启" : "辅助功能未开启")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(appState.accessibilityEnabled ? .green : .orange)
                Button("请求权限") {
                    appState.requestAccessibilityPermission()
                }
            }
            if !appState.accessibilityEnabled {
                Text("点击请求权限后，在系统弹窗中打开系统设置并开启 GTrans。如果系统设置中已开启但这里仍显示未开启，请删除 GTrans 后重新授权。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            Text("LLM 配置")
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
                    syncBaseURLText()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 26, height: 24)
                }
                .help("新增配置")
                Button {
                    appState.deleteSelectedProfile()
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
        return Button {
            commitBaseURLText()
            appState.selectProfile(id: profile.id)
            syncBaseURLText()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(profile.isConfigured ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(profile.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
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
        let status = profile.isConfigured ? "可用" : "未完成"
        return "\(model.isEmpty ? "未填写 model" : model) · \(status)"
    }

    private var profileEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("配置详情")
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                labeledTextField("名称", text: profileStringBinding(\.name))
                labeledTextField("base_url", text: $baseURLText)
                    .onSubmit(commitBaseURLText)
                labeledSecureField("api_key", text: profileStringBinding(\.apiKey))
                labeledTextField("model", text: profileStringBinding(\.model))
            }
            Text("当前用于翻译面板快速切换")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("测试连接") {
                    commitBaseURLText()
                    appState.testSelectedProfileConnection()
                }
                Spacer()
                Button("保存配置") {
                    commitBaseURLText()
                    appState.saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            if let error = appState.setupError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(error == "连接测试通过。" ? .green : .orange)
            }
            Spacer()
        }
    }

    private var preferenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("偏好")
                .font(.headline)
            HStack(spacing: 18) {
                Picker("默认目标语言", selection: $appState.configuration.targetLanguage) {
                    ForEach(TargetLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .frame(width: 220)
                Toggle("使用流式输出", isOn: $appState.configuration.streamingEnabled)
                Toggle("开机自动启动", isOn: $appState.configuration.launchAtLogin)
                    .onChange(of: appState.configuration.launchAtLogin) { enabled in
                        setLaunchAtLogin(enabled)
                    }
                Spacer()
            }
            HStack(spacing: 12) {
                Text("快捷键：Option + Space")
                Text("翻译文本会发送到当前选中的 LLM API endpoint。")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func labeledSecureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            SecureField(label, text: text)
                .textFieldStyle(.roundedBorder)
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
    }
}
