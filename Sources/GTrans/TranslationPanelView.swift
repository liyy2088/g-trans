import GTransCore
import AppKit
import SwiftUI

struct TranslationPanelView: View {
    @ObservedObject var appState: AppState
    @State private var mode: PanelMode
    @State private var manualText = ""
    @State private var manualHasMarkedText = false
    @State private var followUpText = ""
    @State private var sourceTextHeight: CGFloat = 28
    @State private var hoveredActionTitle: String?
    @State private var showingContextDebug = false
    @State private var keepOutputAtTopDuringRegeneration = false
    @State private var outputTopScrollRequest = 0
    @AppStorage("resultActionStackExpanded.v2") private var actionStackExpanded = false
    @FocusState private var manualFocused: Bool
    @FocusState private var followUpFocused: Bool
    private let outputTopID = "output-top"
    private let outputBottomID = "output-bottom"
    private let floatingActionRailWidth: CGFloat = 52
    private let sourceTextMinHeight: CGFloat = 28
    private let sourceTextMaxHeight: CGFloat = 160

    private enum FloatingAction: String, Identifiable {
        case copyTranslation
        case regenerate
        case newTranslation
        case explainUsage
        case examples
        case naturalExpression
        case grammar
        case copySource
        case context
        case settings

        var id: String { rawValue }
    }

    private let primaryFloatingActions: [FloatingAction] = [
        .regenerate,
        .newTranslation
    ]
    private let expandedFloatingActions: [FloatingAction] = [
        .explainUsage,
        .examples,
        .naturalExpression,
        .grammar,
        .context
    ]

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
        .frame(minWidth: 680, minHeight: 520)
        .onAppear {
            if mode == .manualInput {
                manualFocused = true
            } else {
                followUpFocused = true
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .sheet(isPresented: $showingContextDebug) {
            if let snapshot = appState.session.lastLLMContextSnapshot {
                LLMContextDebugView(
                    snapshot: snapshot,
                    sourceText: appState.session.sourceText,
                    translation: appState.session.translation,
                    keywordExplanation: appState.session.keywordExplanation,
                    followUps: appState.session.followUps,
                    stateTitle: appState.session.state.debugDisplayName
                )
            } else {
                Text("暂无 LLM 上下文")
                    .frame(width: 360, height: 160)
            }
        }
    }

    private var manualInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor.opacity(0.85))
                }
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("输入要翻译的文本")
                        .font(.headline)
                    Text("粘贴或输入文本后开始翻译")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let message = appState.panelMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ManualTextEditor(
                        text: $manualText,
                        hasMarkedText: $manualHasMarkedText,
                        isFocused: manualFocused
                    )
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    if manualText.isEmpty && !manualHasMarkedText {
                        Text("在这里输入或粘贴要翻译的文本...")
                            .font(.body)
                            .foregroundStyle(.secondary.opacity(0.75))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 170)
                HStack(alignment: .center, spacing: 10) {
                    Text("\(manualText.count) 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                        .frame(height: 18)
                    Text("Esc 关闭")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    profileMenu
                    Label("自动识别 → \(manualTargetLanguage.displayName)", systemImage: "globe")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Color.secondary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button {
                        appState.startTranslation(text: manualText)
                        mode = .result
                    } label: {
                        Label("翻译", systemImage: "paperplane.fill")
                            .labelStyle(.titleAndIcon)
                            .frame(minWidth: 70)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !appState.isAPIConfigured)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .frame(minHeight: 210)
            .background(Color.secondary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(manualFocused ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private var manualTargetLanguage: TargetLanguage {
        LanguageDirection.targetLanguage(
            for: manualText,
            defaultTarget: appState.configuration.targetLanguage
        )
    }

    private var resultView: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                sourcePreview
                    .padding(.trailing, floatingActionRailWidth)
                Divider()
                translationArea
                followUpInput
            }
            floatingActions
                .padding(.trailing, 2)
                .padding(.bottom, 108)
        }
    }

    private var sourcePreview: some View {
        SelectableSourceText(text: appState.session.sourceText, measuredHeight: $sourceTextHeight)
            .frame(height: sourceVisibleHeight)
    }

    private var sourceVisibleHeight: CGFloat {
        min(max(sourceTextHeight, sourceTextMinHeight), sourceTextMaxHeight)
    }

    private var translationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear
                        .frame(height: 1)
                        .id(outputTopID)
                    Text(appState.session.translation.isEmpty ? "正在翻译..." : appState.session.translation)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    if shouldShowKeywordExplanation {
                        keywordExplanationSection
                    }
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
                .padding(.trailing, floatingActionRailWidth)
            }
            .onChange(of: appState.session.translation) { _ in
                scrollOutputAfterTranslationChange(proxy)
            }
            .onChange(of: appState.session.keywordExplanation) { _ in
                scrollOutputAfterTranslationChange(proxy)
            }
            .onChange(of: appState.session.followUps.count) { _ in
                scrollOutputToBottom(proxy)
            }
            .onChange(of: appState.session.followUps.last?.answer ?? "") { _ in
                scrollOutputToBottom(proxy)
            }
            .onChange(of: appState.session.state) { _ in
                finishKeepingOutputAtTopIfNeeded()
            }
            .onChange(of: outputTopScrollRequest) { _ in
                scrollOutputToTop(proxy)
            }
        }
        .frame(minHeight: 170)
    }

    private var shouldShowKeywordExplanation: Bool {
        visibleKeywordExplanation != nil || isExplainingKeywords
    }

    private var visibleKeywordExplanation: String? {
        let text = appState.session.keywordExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        let emptyKeywordMessages = [
            "无需要特别解释的关键词汇",
            "无需特别解释的关键词汇"
        ]
        let normalizedText = text.trimmingCharacters(in: CharacterSet(charactersIn: "。.!！"))
        guard !emptyKeywordMessages.contains(normalizedText) else {
            return nil
        }
        return text
    }

    private var keywordExplanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("关键词汇")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(visibleKeywordExplanation ?? "正在解释关键词...")
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }

    private func scrollOutputToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(outputBottomID, anchor: .bottom)
            }
        }
    }

    private func scrollOutputToTop(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(outputTopID, anchor: .top)
            }
        }
    }

    private func scrollOutputAfterTranslationChange(_ proxy: ScrollViewProxy) {
        if keepOutputAtTopDuringRegeneration {
            scrollOutputToTop(proxy)
        } else {
            scrollOutputToBottom(proxy)
        }
    }

    private func finishKeepingOutputAtTopIfNeeded() {
        guard keepOutputAtTopDuringRegeneration else {
            return
        }
        switch appState.session.state {
        case .translating, .explainingKeywords:
            return
        case .idle, .failed, .cancelled, .asking:
            DispatchQueue.main.async {
                switch appState.session.state {
                case .translating, .explainingKeywords:
                    return
                case .idle, .failed, .cancelled, .asking:
                    keepOutputAtTopDuringRegeneration = false
                }
            }
        }
    }

    private var floatingActions: some View {
        VStack(alignment: .trailing, spacing: 5) {
            ForEach(primaryFloatingActions) { action in
                floatingActionView(action)
            }
            if actionStackExpanded {
                Group {
                    ForEach(expandedFloatingActions) { action in
                        floatingActionView(action)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            floatingActionButton(
                title: actionStackExpanded ? "折叠" : "更多",
                systemImage: actionStackExpanded ? "chevron.down" : "ellipsis",
                isSelected: actionStackExpanded
            ) {
                withAnimation(.easeOut(duration: 0.16)) {
                    actionStackExpanded.toggle()
                }
            }
        }
    }

    @ViewBuilder
    private func floatingActionView(_ action: FloatingAction) -> some View {
        switch action {
        case .copyTranslation:
            floatingActionButton(
                title: appState.copiedTranslationFeedback ? "已复制译文" : "复制译文",
                systemImage: appState.copiedTranslationFeedback ? "checkmark" : "doc.on.doc",
                isDisabled: appState.session.translation.isEmpty
            ) {
                appState.copyTranslation()
            }
        case .regenerate:
            floatingActionButton(
                title: "重新生成",
                systemImage: "arrow.clockwise",
                loadingTitle: "正在重新生成",
                isLoading: isTranslating,
                isDisabled: appState.session.sourceText.isEmpty || isExplainingKeywords || isAskingFollowUp
            ) {
                keepOutputAtTopDuringRegeneration = true
                outputTopScrollRequest += 1
                appState.regenerate()
                finishKeepingOutputAtTopIfNeeded()
            }
        case .newTranslation:
            floatingActionButton(
                title: "新翻译",
                systemImage: "plus.rectangle.on.rectangle",
                isEmphasized: true
            ) {
                beginNewTranslation()
            }
        case .explainUsage:
            followUpFloatingAction("解释用法", systemImage: "book")
        case .examples:
            followUpFloatingAction("给例句", systemImage: "text.bubble")
        case .naturalExpression:
            followUpFloatingAction("更自然表达", systemImage: "sparkles")
        case .grammar:
            followUpFloatingAction("语法分析", systemImage: "text.alignleft")
        case .copySource:
            floatingActionButton(
                title: appState.copiedSourceFeedback ? "已复制原文" : "复制原文",
                systemImage: appState.copiedSourceFeedback ? "checkmark" : "doc.on.clipboard",
                isDisabled: appState.session.sourceText.isEmpty
            ) {
                appState.copySourceText()
            }
        case .context:
            floatingActionButton(
                title: "查看上下文",
                systemImage: "doc.text",
                isDisabled: shouldDisableContextAction
            ) {
                showingContextDebug = true
            }
        case .settings:
            floatingActionButton(
                title: "设置...",
                systemImage: "gearshape"
            ) {
                appState.openSettings()
            }
        }
    }

    private func followUpFloatingAction(_ title: String, systemImage: String) -> some View {
        floatingActionButton(
            title: title,
            systemImage: systemImage,
            isLoading: isActiveFollowUp(title),
            isDisabled: shouldDisableFollowUpAction(title)
        ) {
            askQuickFollowUp(title)
        }
    }

    private func askQuickFollowUp(_ title: String) {
        appState.ask(
            PromptBuilder.quickFollowUpQuestion(for: title, targetLanguage: appState.session.targetLanguage),
            displayQuestion: title
        )
    }

    private var isAskingFollowUp: Bool {
        if case .asking = appState.session.state {
            return true
        }
        return false
    }

    private var isTranslating: Bool {
        if case .translating = appState.session.state {
            return true
        }
        return false
    }

    private var isExplainingKeywords: Bool {
        if case .explainingKeywords = appState.session.state {
            return true
        }
        return false
    }

    private func isActiveFollowUp(_ title: String) -> Bool {
        appState.session.activeFollowUpQuestion == title
    }

    private func shouldDisableFollowUpAction(_ title: String) -> Bool {
        appState.session.translation.isEmpty || isTranslating || isExplainingKeywords || (isAskingFollowUp && !isActiveFollowUp(title))
    }

    private var shouldDisableContextAction: Bool {
        appState.session.lastLLMContextSnapshot == nil || isTranslating || isExplainingKeywords || isAskingFollowUp
    }

    private func floatingActionButton(
        title: String,
        systemImage: String,
        isEmphasized: Bool = false,
        isSelected: Bool = false,
        loadingTitle: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let visibleTitle = isLoading ? (loadingTitle ?? "正在\(title)") : title
        return HStack(spacing: 8) {
            if hoveredActionTitle == title {
                Text(visibleTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            Button(action: action) {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 34, height: 34)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 34, height: 34)
                    }
                }
                .contentShape(Rectangle())
                .background(floatingActionBackground(isEmphasized: isEmphasized, isSelected: isSelected || isLoading))
                .foregroundStyle(isEmphasized ? Color.accentColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(floatingActionStroke(isEmphasized: isEmphasized, isSelected: isSelected || isLoading), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .help(visibleTitle)
            .accessibilityLabel(visibleTitle)
            .disabled(isDisabled || isLoading)
            .opacity((isDisabled && !isLoading) ? 0.45 : 1)
        }
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.10)) {
                hoveredActionTitle = isHovering ? title : nil
            }
        }
    }

    private func floatingActionBackground(isEmphasized: Bool, isSelected: Bool) -> Color {
        if isEmphasized {
            return Color.accentColor.opacity(0.16)
        }
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.92)
    }

    private func floatingActionStroke(isEmphasized: Bool, isSelected: Bool) -> Color {
        if isEmphasized || isSelected {
            return Color.accentColor.opacity(0.32)
        }
        return Color.secondary.opacity(0.18)
    }

    private var followUpTargetLanguage: TargetLanguage {
        appState.session.targetLanguage
    }

    private var followUpStatusLine: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(followUpText.count) 字")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
                .frame(height: 16)
            Text("Esc 关闭")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            profileMenu
            Label("自动识别 → \(followUpTargetLanguage.displayName)", systemImage: "globe")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Button {
                sendFollowUp()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSendFollowUp ? Color.accentColor : Color.secondary.opacity(0.45))
            .disabled(!canSendFollowUp)
            .accessibilityLabel("发送")
        }
    }

    private var followUpInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor.opacity(0.85))
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
                TextField("继续追问", text: $followUpText)
                    .focused($followUpFocused)
                    .textFieldStyle(.plain)
                    .onSubmit(sendFollowUp)
            }
            followUpStatusLine
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 82)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(followUpFocused ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    private var canSendFollowUp: Bool {
        appState.isAPIConfigured &&
            !isAskingFollowUp &&
            !isTranslating &&
            !isExplainingKeywords &&
            !followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var profileMenu: some View {
        Menu {
            ForEach(appState.configuration.profiles) { profile in
                Button {
                    appState.selectProfile(id: profile.id)
                } label: {
                    if appState.configuration.selectedProfile?.id == profile.id {
                        Label(profile.displayName, systemImage: "checkmark")
                    } else {
                        Text(profile.displayName)
                    }
                }
            }
            Divider()
            Button("管理配置...") {
                appState.openSettings()
            }
        } label: {
            Label(profileMenuTitle, systemImage: "cpu")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .foregroundStyle(appState.isAPIConfigured ? Color.primary.opacity(0.85) : Color.orange)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var profileMenuTitle: String {
        guard let profile = appState.selectedProfile else {
            return "未配置 LLM"
        }
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty {
            return profile.displayName
        }
        return "\(profile.displayName) · \(model)"
    }

    private func sendFollowUp() {
        let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        followUpText = ""
        appState.ask(text)
    }

    private func beginNewTranslation() {
        appState.startNewTranslationDraft()
        manualText = ""
        manualHasMarkedText = false
        followUpText = ""
        hoveredActionTitle = nil
        mode = .manualInput
        DispatchQueue.main.async {
            manualFocused = true
        }
    }
}

private struct LLMContextDebugView: View {
    let snapshot: LLMContextSnapshot
    let sourceText: String
    let translation: String
    let keywordExplanation: String
    let followUps: [FollowUpTurn]
    let stateTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    metadata
                    messages
                    sessionSummary
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 560)
        .onExitCommand {
            dismiss()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("LLM 上下文")
                    .font(.headline)
                Text("最后一次\(snapshot.requestKind.displayName)请求")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Esc 关闭")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("请求信息")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.fixed(110), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                metadataRow("类型", snapshot.requestKind.displayName)
                metadataRow("配置", snapshot.profileName)
                metadataRow("Base URL", snapshot.baseURL.absoluteString)
                metadataRow("Model", snapshot.model)
                metadataRow("Streaming", snapshot.streamingEnabled ? "开启" : "关闭")
                metadataRow("目标语言", snapshot.targetLanguage.displayName)
                metadataRow("时间", Self.dateFormatter.string(from: snapshot.createdAt))
            }
        }
        .debugSectionStyle()
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        Group {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "未设置" : value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private var messages: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Messages")
                .font(.subheadline.weight(.semibold))
            ForEach(Array(snapshot.messages.enumerated()), id: \.offset) { index, message in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.secondary.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(message.role)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(roleColor(message.role))
                        Spacer()
                        Text("\(message.content.count) 字")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(message.content)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .debugMessageStyle()
            }
        }
        .debugSectionStyle()
    }

    private var sessionSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前会话")
                .font(.subheadline.weight(.semibold))
            summaryBlock(title: "状态", text: stateTitle)
            summaryBlock(title: "原文", text: sourceText)
            summaryBlock(title: "译文", text: translation.isEmpty ? "暂无译文" : translation)
            summaryBlock(title: "关键词汇", text: keywordExplanation.isEmpty ? "暂无关键词解释" : keywordExplanation)
            if followUps.isEmpty {
                summaryBlock(title: "追问", text: "暂无追问")
            } else {
                ForEach(Array(followUps.enumerated()), id: \.offset) { index, turn in
                    summaryBlock(title: "追问 \(index + 1)", text: "Q: \(turn.question)\nA: \(turn.answer.isEmpty ? "正在回答..." : turn.answer)")
                }
            }
        }
        .debugSectionStyle()
    }

    private func summaryBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("复制内容不包含 API Key")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            debugActionButton(title: "复制文本", systemImage: "doc.on.doc") {
                copy(snapshot.plainTextDescription())
            }
            debugActionButton(title: "复制 JSON", systemImage: "curlybraces") {
                copy(snapshot.jsonString())
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .padding(18)
    }

    private func debugActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                .foregroundStyle(Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "system":
            return .purple
        case "user":
            return .accentColor
        case "assistant":
            return .green
        default:
            return .secondary
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private extension View {
    func debugSectionStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            )
    }

    func debugMessageStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
            )
    }
}

private extension TranslationState {
    var debugDisplayName: String {
        switch self {
        case .idle:
            return "空闲"
        case .translating:
            return "正在翻译"
        case .explainingKeywords:
            return "正在解释关键词"
        case .asking:
            return "正在追问"
        case .failed(let message):
            return "失败：\(message)"
        case .cancelled:
            return "已取消"
        }
    }
}

private struct SelectableSourceText: NSViewRepresentable {
    let text: String
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(measuredHeight: $measuredHeight)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MeasuringScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.onLayout = {
            context.coordinator.updateMeasuredHeight(in: scrollView)
        }

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.preferredFont(forTextStyle: .callout)
        textView.textColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text

        applyLayout(to: textView, in: scrollView)
        scrollView.documentView = textView
        context.coordinator.updateMeasuredHeight(in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        if textView.string != text {
            textView.string = text
        }
        applyLayout(to: textView, in: scrollView)
        context.coordinator.updateMeasuredHeight(in: scrollView)
    }

    private func applyLayout(to textView: NSTextView, in scrollView: NSScrollView) {
        textView.textContainer?.maximumNumberOfLines = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
    }

    final class Coordinator {
        @Binding private var measuredHeight: CGFloat

        init(measuredHeight: Binding<CGFloat>) {
            _measuredHeight = measuredHeight
        }

        func updateMeasuredHeight(in scrollView: NSScrollView) {
            guard let textView = scrollView.documentView as? NSTextView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else {
                return
            }

            textContainer.containerSize = NSSize(
                width: scrollView.contentSize.width,
                height: .greatestFiniteMagnitude
            )
            layoutManager.ensureLayout(for: textContainer)
            let contentHeight = ceil(layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2)

            DispatchQueue.main.async {
                if abs(self.measuredHeight - contentHeight) > 0.5 {
                    self.measuredHeight = contentHeight
                }
            }
        }
    }

    final class MeasuringScrollView: NSScrollView {
        var onLayout: (() -> Void)?

        override func layout() {
            super.layout()
            onLayout?()
        }
    }
}

private struct ManualTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var hasMarkedText: Bool
    let isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, hasMarkedText: $hasMarkedText)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = ReportingTextView()
        textView.delegate = context.coordinator
        textView.onMarkedTextChange = { hasMarkedText in
            context.coordinator.updateMarkedText(hasMarkedText)
        }
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
        }

        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var hasMarkedText: Bool
        weak var textView: ReportingTextView?

        init(text: Binding<String>, hasMarkedText: Binding<Bool>) {
            _text = text
            _hasMarkedText = hasMarkedText
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text = textView.string
            updateMarkedText(textView.hasMarkedText())
        }

        func updateMarkedText(_ value: Bool) {
            guard hasMarkedText != value else {
                return
            }
            DispatchQueue.main.async {
                self.hasMarkedText = value
            }
        }
    }

    final class ReportingTextView: NSTextView {
        var onMarkedTextChange: ((Bool) -> Void)?

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            notifyMarkedTextChange()
        }

        override func unmarkText() {
            super.unmarkText()
            notifyMarkedTextChange()
        }

        override func insertText(_ insertString: Any, replacementRange: NSRange) {
            super.insertText(insertString, replacementRange: replacementRange)
            notifyMarkedTextChange()
        }

        private func notifyMarkedTextChange() {
            let value = hasMarkedText()
            DispatchQueue.main.async { [weak self] in
                self?.onMarkedTextChange?(value)
            }
        }
    }
}
