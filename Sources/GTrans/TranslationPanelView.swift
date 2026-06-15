import GTransCore
import AppKit
import SwiftUI

struct TranslationPanelView: View {
    @ObservedObject var appState: AppState
    @State private var mode: PanelMode
    @State private var manualText = ""
    @State private var manualHasMarkedText = false
    @State private var followUpText = ""
    @State private var sourceExpanded = false
    @State private var hoveredActionTitle: String?
    @AppStorage("resultActionStackExpanded.v2") private var actionStackExpanded = false
    @FocusState private var manualFocused: Bool
    @FocusState private var followUpFocused: Bool
    private let outputBottomID = "output-bottom"
    private let floatingActionRailWidth: CGFloat = 52

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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("原文")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if sourceCanExpand {
                    Button(action: toggleSourceExpansion) {
                        SourceExpansionIcon(isExpanded: sourceExpanded)
                            .frame(width: 24, height: 24)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(sourceExpanded ? "收起原文" : "展开原文")
                    .accessibilityLabel(sourceExpanded ? "收起原文" : "展开原文")
                }
            }
            if sourceExpanded {
                SelectableSourceText(text: appState.session.sourceText, isExpanded: true)
                    .frame(maxHeight: 160)
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                SelectableSourceText(text: appState.session.sourceText, isExpanded: false)
                    .frame(height: 22)
            }
        }
    }

    private func toggleSourceExpansion() {
        guard sourceCanExpand else {
            return
        }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            sourceExpanded.toggle()
        }
    }

    private var sourceCanExpand: Bool {
        appState.session.sourceText.count > 120 || appState.session.sourceText.split(whereSeparator: \.isNewline).count > 3
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
                .padding(.trailing, floatingActionRailWidth)
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

    private var floatingActions: some View {
        VStack(alignment: .trailing, spacing: 5) {
            floatingActionButton(
                title: appState.copiedTranslationFeedback ? "已复制译文" : "复制译文",
                systemImage: appState.copiedTranslationFeedback ? "checkmark" : "doc.on.doc",
                isDisabled: appState.session.translation.isEmpty
            ) {
                appState.copyTranslation()
            }
            floatingActionButton(
                title: "重新生成",
                systemImage: "arrow.clockwise",
                loadingTitle: "正在重新生成",
                isLoading: isTranslating,
                isDisabled: appState.session.sourceText.isEmpty || isAskingFollowUp
            ) {
                appState.regenerate()
            }
            floatingActionButton(
                title: "新翻译",
                systemImage: "plus.rectangle.on.rectangle",
                isEmphasized: true
            ) {
                beginNewTranslation()
            }
            if actionStackExpanded {
                Group {
                    floatingActionButton(
                        title: "解释用法",
                        systemImage: "book",
                        isLoading: isActiveFollowUp("解释用法"),
                        isDisabled: shouldDisableFollowUpAction("解释用法")
                    ) {
                        askSourceFocused("解释用法")
                    }
                    floatingActionButton(
                        title: "给例句",
                        systemImage: "text.bubble",
                        isLoading: isActiveFollowUp("给例句"),
                        isDisabled: shouldDisableFollowUpAction("给例句")
                    ) {
                        askSourceFocused("给例句")
                    }
                    floatingActionButton(
                        title: "更自然表达",
                        systemImage: "sparkles",
                        isLoading: isActiveFollowUp("更自然表达"),
                        isDisabled: shouldDisableFollowUpAction("更自然表达")
                    ) {
                        askSourceFocused("更自然表达")
                    }
                    floatingActionButton(
                        title: "语法分析",
                        systemImage: "text.alignleft",
                        isLoading: isActiveFollowUp("语法分析"),
                        isDisabled: shouldDisableFollowUpAction("语法分析")
                    ) {
                        askSourceFocused("语法分析")
                    }
                    floatingActionButton(
                        title: appState.copiedSourceFeedback ? "已复制原文" : "复制原文",
                        systemImage: appState.copiedSourceFeedback ? "checkmark" : "doc.on.clipboard",
                        isDisabled: appState.session.sourceText.isEmpty
                    ) {
                        appState.copySourceText()
                    }
                    floatingActionButton(
                        title: "设置...",
                        systemImage: "gearshape"
                    ) {
                        appState.openSettings()
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

    private func askSourceFocused(_ title: String) {
        appState.ask(PromptBuilder.sourceFocusedFollowUpQuestion(for: title), displayQuestion: title)
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

    private func isActiveFollowUp(_ title: String) -> Bool {
        appState.session.activeFollowUpQuestion == title
    }

    private func shouldDisableFollowUpAction(_ title: String) -> Bool {
        appState.session.translation.isEmpty || isTranslating || (isAskingFollowUp && !isActiveFollowUp(title))
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
        sourceExpanded = false
        hoveredActionTitle = nil
        mode = .manualInput
        DispatchQueue.main.async {
            manualFocused = true
        }
    }
}

private struct SourceExpansionIcon: View {
    let isExpanded: Bool

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let size = min(proxy.size.width, proxy.size.height)
                let inset = isExpanded ? size * 0.22 : size * 0.28
                let length = isExpanded ? size * 0.16 : size * 0.18
                if isExpanded {
                    addCollapseCorners(to: &path, inset: inset, length: length, size: size)
                } else {
                    addExpandCorners(to: &path, inset: inset, length: length, size: size)
                }
            }
            .stroke(
                Color.primary.opacity(0.68),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .butt, lineJoin: .miter)
            )
        }
        .padding(1)
    }

    private func addExpandCorners(to path: inout Path, inset: CGFloat, length: CGFloat, size: CGFloat) {
        let min = inset
        let max = size - inset

        // 展开：左上和右下两角向外打开。
        path.move(to: CGPoint(x: min + length, y: min))
        path.addLine(to: CGPoint(x: min, y: min))
        path.addLine(to: CGPoint(x: min, y: min + length))

        path.move(to: CGPoint(x: max - length, y: max))
        path.addLine(to: CGPoint(x: max, y: max))
        path.addLine(to: CGPoint(x: max, y: max - length))
    }

    private func addCollapseCorners(to path: inout Path, inset: CGFloat, length: CGFloat, size: CGFloat) {
        let min = inset
        let max = size - inset

        // 收起：保持同一条左上-右下轴，角标方向向内收拢。
        path.move(to: CGPoint(x: min, y: min + length))
        path.addLine(to: CGPoint(x: min + length, y: min + length))
        path.addLine(to: CGPoint(x: min + length, y: min))

        path.move(to: CGPoint(x: max, y: max - length))
        path.addLine(to: CGPoint(x: max - length, y: max - length))
        path.addLine(to: CGPoint(x: max - length, y: max))
    }
}

private struct SelectableSourceText: NSViewRepresentable {
    let text: String
    let isExpanded: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = isExpanded
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

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

        applyLayout(to: textView)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.hasVerticalScroller = isExpanded
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        if textView.string != text {
            textView.string = text
        }
        applyLayout(to: textView)
    }

    private func applyLayout(to textView: NSTextView) {
        textView.textContainer?.maximumNumberOfLines = isExpanded ? 0 : 1
        textView.textContainer?.lineBreakMode = isExpanded ? .byWordWrapping : .byTruncatingTail
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
