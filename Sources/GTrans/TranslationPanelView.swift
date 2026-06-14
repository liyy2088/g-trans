import GTransCore
import SwiftUI

struct TranslationPanelView: View {
    @ObservedObject var appState: AppState
    @State private var mode: PanelMode
    @State private var manualText = ""
    @State private var followUpText = ""
    @State private var sourceExpanded = false
    @FocusState private var manualFocused: Bool
    @FocusState private var followUpFocused: Bool
    private let outputBottomID = "output-bottom"

    init(appState: AppState, initialMode: PanelMode) {
        self.appState = appState
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode == .manualInput {
                manualInput
            } else {
                resultView
            }
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            if mode == .manualInput {
                manualFocused = true
            } else {
                followUpFocused = true
            }
        }
    }

    private var manualInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("输入要翻译的文本")
                .font(.headline)
            if let message = appState.panelMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            TextEditor(text: $manualText)
                .font(.body)
                .frame(minHeight: 210)
                .padding(8)
                .focused($manualFocused)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25))
                )
            HStack {
                Spacer()
                Button("关闭") {
                    appState.requestClosePanel()
                }
                Button("翻译") {
                    appState.startTranslation(text: manualText)
                    mode = .result
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 12) {
            sourcePreview
            Divider()
            translationArea
            actions
            quickQuestions
            followUpInput
        }
    }

    private var sourcePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("原文")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(sourceExpanded ? "收起" : "展开") {
                    sourceExpanded.toggle()
                }
                .buttonStyle(.plain)
            }
            if sourceExpanded {
                ScrollView {
                    Text(appState.session.sourceText)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(appState.session.sourceText)
                    .font(.callout)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
    }

    private var translationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(appState.session.translation.isEmpty ? "正在翻译..." : appState.session.translation)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    ForEach(Array(appState.session.followUps.enumerated()), id: \.offset) { _, turn in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(turn.question)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(turn.answer.isEmpty ? "正在回答..." : turn.answer)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if case .failed(let message) = appState.session.state {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(outputBottomID)
                }
            }
            .onChange(of: appState.session.translation) { _ in
                scrollOutputToBottom(proxy)
            }
            .onChange(of: appState.session.followUps.count) { _ in
                scrollOutputToBottom(proxy)
            }
            .onChange(of: appState.session.followUps.last?.answer ?? "") { _ in
                scrollOutputToBottom(proxy)
            }
        }
        .frame(minHeight: 170)
    }

    private func scrollOutputToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(outputBottomID, anchor: .bottom)
            }
        }
    }

    private var actions: some View {
        HStack {
            HStack(spacing: 0) {
                toolButton(
                    title: appState.copiedFeedback ? "已复制" : "复制译文",
                    systemImage: appState.copiedFeedback ? "checkmark" : "doc.on.doc",
                    isDisabled: appState.session.translation.isEmpty
                ) {
                    appState.copyTranslation()
                }
                toolDivider
                toolButton(
                    title: "重新生成",
                    systemImage: "arrow.clockwise",
                    isDisabled: appState.session.sourceText.isEmpty
                ) {
                    appState.regenerate()
                }
                toolDivider
                toolButton(
                    title: "新翻译",
                    systemImage: "plus.rectangle.on.rectangle",
                    isEmphasized: true
                ) {
                    beginNewTranslation()
                }
                toolDivider
                toolButton(title: "关闭", systemImage: "xmark") {
                    appState.requestClosePanel()
                }
            }
            .padding(3)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.12))
            )
            Spacer()
        }
    }

    private var toolDivider: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 2)
    }

    private func toolButton(
        title: String,
        systemImage: String,
        isEmphasized: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(isEmphasized ? Color.accentColor.opacity(0.14) : Color.clear)
                .foregroundStyle(isEmphasized ? Color.accentColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var quickQuestions: some View {
        HStack {
            ForEach(["解释用法", "给例句", "更自然表达", "语法分析"], id: \.self) { title in
                Button(title) {
                    appState.ask(title)
                }
                .disabled(appState.session.translation.isEmpty)
            }
        }
    }

    private var followUpInput: some View {
        HStack {
            TextField("继续追问", text: $followUpText)
                .focused($followUpFocused)
                .textFieldStyle(.roundedBorder)
                .onSubmit(sendFollowUp)
            Button("发送") {
                sendFollowUp()
            }
            .disabled(followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func sendFollowUp() {
        let text = followUpText
        followUpText = ""
        appState.ask(text)
    }

    private func beginNewTranslation() {
        appState.startNewTranslationDraft()
        manualText = ""
        followUpText = ""
        sourceExpanded = false
        mode = .manualInput
        DispatchQueue.main.async {
            manualFocused = true
        }
    }
}
