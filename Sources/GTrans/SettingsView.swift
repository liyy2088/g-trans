import GTransCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var baseURLText = ""

    var body: some View {
        Form {
            Section("权限") {
                HStack {
                    Text("辅助功能权限")
                    Spacer()
                    Text(appState.accessibilityEnabled ? "已开启" : "未开启")
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

            Section("LLM 配置") {
                TextField("base_url", text: $baseURLText)
                    .onSubmit(updateBaseURL)
                SecureField("api_key", text: $appState.apiKey)
                TextField("model", text: $appState.configuration.model)
                Toggle("使用流式输出", isOn: $appState.configuration.streamingEnabled)
                Button("保存配置") {
                    updateBaseURL()
                    appState.saveSettings()
                }
                if let error = appState.setupError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section("偏好") {
                Picker("默认目标语言", selection: $appState.configuration.targetLanguage) {
                    ForEach(TargetLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                Toggle("开机自动启动", isOn: $appState.configuration.launchAtLogin)
                    .onChange(of: appState.configuration.launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                Text("快捷键：Option + Space")
                    .foregroundStyle(.secondary)
                Text("翻译文本会发送到你配置的 LLM API endpoint。G-Trans 不保存翻译历史，不做遥测。API Key 保存在本机偏好设置中。")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 460)
        .onAppear {
            baseURLText = appState.configuration.baseURL.absoluteString
            appState.refreshAccessibilityStatus()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            appState.refreshAccessibilityStatus()
        }
    }

    private func updateBaseURL() {
        if let url = URL(string: baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            appState.configuration.baseURL = url
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
