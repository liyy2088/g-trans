import Combine
import Foundation

public struct FollowUpTurn: Codable, Equatable, Sendable {
    public var question: String
    public var llmQuestion: String?
    public var answer: String

    public init(question: String, llmQuestion: String? = nil, answer: String) {
        self.question = question
        self.llmQuestion = llmQuestion
        self.answer = answer
    }

    public var modelQuestion: String {
        llmQuestion ?? question
    }
}

public enum TranslationState: Equatable, Sendable {
    case idle
    case translating
    case asking
    case failed(String)
    case cancelled
}

@MainActor
public final class TranslationSession: ObservableObject {
    @Published public private(set) var sourceText: String
    @Published public private(set) var targetLanguage: TargetLanguage
    @Published public var translation: String
    @Published public var followUps: [FollowUpTurn]
    @Published public private(set) var activeFollowUpQuestion: String?
    @Published public private(set) var lastLLMContextSnapshot: LLMContextSnapshot?
    @Published public var state: TranslationState
    @Published public var isClosed: Bool
    private var task: Task<Void, Never>?

    public init(sourceText: String = "", targetLanguage: TargetLanguage = .simplifiedChinese) {
        self.sourceText = sourceText
        self.targetLanguage = targetLanguage
        self.translation = ""
        self.followUps = []
        self.activeFollowUpQuestion = nil
        self.lastLLMContextSnapshot = nil
        self.state = .idle
        self.isClosed = false
    }

    public func start(sourceText: String, targetLanguage: TargetLanguage) {
        cancel()
        self.sourceText = sourceText
        self.targetLanguage = targetLanguage
        translation = ""
        followUps = []
        activeFollowUpQuestion = nil
        lastLLMContextSnapshot = nil
        state = .idle
        isClosed = false
    }

    public func runTranslation(client: LLMClient, profile: LLMProfile, streamingEnabled: Bool) {
        cancel()
        translation = ""
        activeFollowUpQuestion = nil
        state = .translating
        AppDiagnostics.info(
            "translation_request_start",
            [
                "source_length": sourceText.count,
                "profile_name": profile.displayName,
                "base_url": profile.baseURL.absoluteString,
                "model": profile.model
            ]
        )
        let messages = PromptBuilder.translationMessages(sourceText: sourceText, targetLanguage: targetLanguage)
        lastLLMContextSnapshot = makeContextSnapshot(
            requestKind: .translation,
            profile: profile,
            streamingEnabled: streamingEnabled,
            messages: messages
        )
        task = Task { [weak self] in
            await self?.consume(client: client, profile: profile, streamingEnabled: streamingEnabled, messages: messages) { session, token in
                session.translation += token
            }
        }
    }

    public func ask(question: String, displayQuestion: String? = nil, client: LLMClient, profile: LLMProfile, streamingEnabled: Bool) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let visibleQuestion = displayQuestion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedQuestion = visibleQuestion.flatMap { $0.isEmpty ? nil : $0 } ?? trimmed
        cancel()
        state = .asking
        activeFollowUpQuestion = storedQuestion
        let historyBeforeQuestion = followUps
        followUps.append(FollowUpTurn(question: storedQuestion, llmQuestion: trimmed, answer: ""))
        var answer = ""
        AppDiagnostics.info(
            "follow_up_request_start",
            [
                "question_length": trimmed.count,
                "profile_name": profile.displayName,
                "base_url": profile.baseURL.absoluteString,
                "model": profile.model
            ]
        )
        let messages = PromptBuilder.followUpMessages(
            sourceText: sourceText,
            translation: translation,
            targetLanguage: targetLanguage,
            history: historyBeforeQuestion,
            question: trimmed
        )
        lastLLMContextSnapshot = makeContextSnapshot(
            requestKind: .followUp,
            profile: profile,
            streamingEnabled: streamingEnabled,
            messages: messages
        )
        task = Task { [weak self] in
            await self?.consume(client: client, profile: profile, streamingEnabled: streamingEnabled, messages: messages) { session, token in
                answer += token
                if session.followUps.last?.question == storedQuestion {
                    session.followUps[session.followUps.count - 1].answer = answer
                } else {
                    session.followUps.append(FollowUpTurn(question: storedQuestion, llmQuestion: trimmed, answer: answer))
                }
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        if state == .translating || state == .asking {
            state = .cancelled
        }
        activeFollowUpQuestion = nil
    }

    public func close() {
        cancel()
        sourceText = ""
        translation = ""
        followUps = []
        activeFollowUpQuestion = nil
        lastLLMContextSnapshot = nil
        state = .idle
        isClosed = true
    }

    private func makeContextSnapshot(
        requestKind: LLMContextRequestKind,
        profile: LLMProfile,
        streamingEnabled: Bool,
        messages: [ChatMessage]
    ) -> LLMContextSnapshot {
        LLMContextSnapshot(
            requestKind: requestKind,
            profileName: profile.displayName,
            baseURL: profile.baseURL,
            model: profile.model,
            streamingEnabled: streamingEnabled,
            targetLanguage: targetLanguage,
            messages: messages,
            sessionSummary: LLMContextSessionSummary(
                sourceText: sourceText,
                translation: translation,
                followUps: followUps,
                state: state.contextDescription
            )
        )
    }

    private func consume(
        client: LLMClient,
        profile: LLMProfile,
        streamingEnabled: Bool,
        messages: [ChatMessage],
        append: @escaping @MainActor (TranslationSession, String) -> Void
    ) async {
        do {
            let stream = try await client.complete(
                profile: profile,
                streamingEnabled: streamingEnabled,
                messages: messages
            )
            var assistantResponse = ""
            for try await token in stream {
                guard !Task.isCancelled, !isClosed else {
                    return
                }
                append(self, token)
                assistantResponse += token
                updateContextAssistantResponse(assistantResponse)
            }
            if !Task.isCancelled, !isClosed {
                state = .idle
                activeFollowUpQuestion = nil
                AppDiagnostics.info("llm_request_finished")
            }
        } catch is CancellationError {
            state = .cancelled
            activeFollowUpQuestion = nil
            AppDiagnostics.info("llm_request_cancelled")
        } catch {
            if !isClosed {
                state = .failed(LLMErrorPresenter.message(for: error))
                activeFollowUpQuestion = nil
                AppDiagnostics.error(
                    "llm_request_failed",
                    [
                        "error_type": String(describing: type(of: error)),
                        "error": error.localizedDescription
                    ]
                )
            }
        }
    }

    private func updateContextAssistantResponse(_ response: String) {
        guard !response.isEmpty,
              var snapshot = lastLLMContextSnapshot else {
            return
        }
        if let lastIndex = snapshot.messages.indices.last,
           snapshot.messages[lastIndex].role == "assistant" {
            snapshot.messages[lastIndex].content = response
        } else {
            snapshot.messages.append(ChatMessage(role: "assistant", content: response))
        }
        lastLLMContextSnapshot = snapshot
    }
}

extension TranslationState {
    var contextDescription: String {
        switch self {
        case .idle:
            return "idle"
        case .translating:
            return "translating"
        case .asking:
            return "asking"
        case .failed(let message):
            return "failed: \(message)"
        case .cancelled:
            return "cancelled"
        }
    }
}
