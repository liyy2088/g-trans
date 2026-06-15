import Combine
import Foundation

public struct FollowUpTurn: Equatable, Sendable {
    public var question: String
    public var answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
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
    @Published public var state: TranslationState
    @Published public var isClosed: Bool
    private var task: Task<Void, Never>?

    public init(sourceText: String = "", targetLanguage: TargetLanguage = .simplifiedChinese) {
        self.sourceText = sourceText
        self.targetLanguage = targetLanguage
        self.translation = ""
        self.followUps = []
        self.state = .idle
        self.isClosed = false
    }

    public func start(sourceText: String, targetLanguage: TargetLanguage) {
        cancel()
        self.sourceText = sourceText
        self.targetLanguage = targetLanguage
        translation = ""
        followUps = []
        state = .idle
        isClosed = false
    }

    public func runTranslation(client: LLMClient, configuration: AppConfiguration, apiKey: String) {
        cancel()
        translation = ""
        state = .translating
        AppDiagnostics.info("translation_request_start", ["source_length": sourceText.count])
        let messages = PromptBuilder.translationMessages(sourceText: sourceText, targetLanguage: targetLanguage)
        task = Task { [weak self] in
            await self?.consume(client: client, configuration: configuration, apiKey: apiKey, messages: messages) { session, token in
                session.translation += token
            }
        }
    }

    public func ask(question: String, displayQuestion: String? = nil, client: LLMClient, configuration: AppConfiguration, apiKey: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let visibleQuestion = displayQuestion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedQuestion = visibleQuestion.flatMap { $0.isEmpty ? nil : $0 } ?? trimmed
        cancel()
        state = .asking
        var answer = ""
        AppDiagnostics.info("follow_up_request_start", ["question_length": trimmed.count])
        let messages = PromptBuilder.followUpMessages(
            sourceText: sourceText,
            translation: translation,
            targetLanguage: targetLanguage,
            history: followUps,
            question: trimmed
        )
        task = Task { [weak self] in
            await self?.consume(client: client, configuration: configuration, apiKey: apiKey, messages: messages) { session, token in
                answer += token
                if session.followUps.last?.question == storedQuestion {
                    session.followUps[session.followUps.count - 1].answer = answer
                } else {
                    session.followUps.append(FollowUpTurn(question: storedQuestion, answer: answer))
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
    }

    public func close() {
        cancel()
        sourceText = ""
        translation = ""
        followUps = []
        state = .idle
        isClosed = true
    }

    private func consume(
        client: LLMClient,
        configuration: AppConfiguration,
        apiKey: String,
        messages: [ChatMessage],
        append: @escaping @MainActor (TranslationSession, String) -> Void
    ) async {
        do {
            let stream = try await client.complete(
                configuration: configuration,
                apiKey: apiKey,
                messages: messages
            )
            for try await token in stream {
                guard !Task.isCancelled, !isClosed else {
                    return
                }
                append(self, token)
            }
            if !Task.isCancelled, !isClosed {
                state = .idle
                AppDiagnostics.info("llm_request_finished")
            }
        } catch is CancellationError {
            state = .cancelled
            AppDiagnostics.info("llm_request_cancelled")
        } catch {
            if !isClosed {
                state = .failed(LLMErrorPresenter.message(for: error))
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
}
