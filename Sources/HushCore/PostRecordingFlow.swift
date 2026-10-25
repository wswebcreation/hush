import Foundation

public enum FlowStep: Int, CaseIterable, Sendable {
    case transcribe, review, notes, generate, finish

    public var label: String {
        switch self {
        case .transcribe: L10n.stepTranscribe
        case .review: L10n.stepReview
        case .notes: L10n.stepNotes
        case .generate: L10n.stepGenerate
        case .finish: L10n.stepFinish
        }
    }
}

public enum StepState: Equatable, Sendable { case completed, current, upcoming, failed }

public enum NotesChoice: Equatable, Sendable {
    case provider(NotesProviderKind)
    case skip
}

/// Pure navigation rules for the post recording window (screens 3.1 to 3.5).
public struct PostRecordingFlow: Equatable, Sendable {
    public var step: FlowStep = .transcribe
    public var failed = false
    /// Once a transcript request has been made, going back would allow a silent re-send.
    public var notesSent = false

    public init(step: FlowStep = .transcribe) { self.step = step }

    public func state(of s: FlowStep) -> StepState {
        if s == step { return failed ? .failed : .current }
        return s.rawValue < step.rawValue ? .completed : .upcoming
    }

    /// "Vorige" is allowed on steps 2 and 3 only.
    public var canGoBack: Bool { (step == .review || step == .notes) && !notesSent }

    public mutating func back() {
        guard canGoBack else { return }
        step = FlowStep(rawValue: step.rawValue - 1)!
    }

    public mutating func transcriptionFinished() { failed = false; step = .review }
    public mutating func transcriptionFailed() { step = .transcribe; failed = true }
    public mutating func retryTranscription() { step = .transcribe; failed = false }
    public mutating func reviewDone() { step = .notes }

    /// Overslaan goes straight to Afronden; a provider sends the transcript and waits.
    public mutating func submitNotes(_ choice: NotesChoice) {
        switch choice {
        case .skip: step = .finish
        case .provider: notesSent = true; failed = false; step = .generate
        }
    }

    public mutating func notesFailed() { step = .generate; failed = true }
    public mutating func retryNotes() { step = .generate; failed = false }
    public mutating func notesDone() { failed = false; step = .generate }
    public mutating func continueToFinish() { failed = false; step = .finish }

    /// The primary button on step 3 is disabled for a provider without a saved key.
    public static func canSubmit(_ choice: NotesChoice, hasKey: (NotesProviderKind) -> Bool) -> Bool {
        switch choice {
        case .skip: true
        case .provider(let p): hasKey(p)
        }
    }

    public static func sendLabel(_ choice: NotesChoice) -> String {
        switch choice {
        case .provider(.claude): L10n.flowSendClaude
        case .provider(.openai): L10n.flowSendOpenAI
        case .skip: L10n.flowContinueNoNotes
        }
    }

    public static func notice(_ choice: NotesChoice) -> String {
        switch choice {
        case .provider(.claude): L10n.flowNoticeClaude
        case .provider(.openai): L10n.flowNoticeOpenAI
        case .skip: L10n.flowNoticeSkip
        }
    }
}

/// Decides whether the "Verwijder de audio-opname" checkbox may be on, and what Klaar does.
public enum AudioDeletionPolicy {
    /// Checkbox forced off when the transcript is missing or empty.
    public static func initialChoice(settingDefault: Bool, transcriptUsable: Bool) -> Bool {
        settingDefault && transcriptUsable
    }

    /// Closing the window with the red button never deletes; only Klaar / Open in Opnamen with the box ticked.
    public static func shouldDelete(checkboxOn: Bool, transcriptUsable: Bool, closedViaWindowButton: Bool) -> Bool {
        checkboxOn && transcriptUsable && !closedViaWindowButton
    }
}

/// Orchestrates notes generation and persistence, with the fail-safe that errors never lose data.
public struct NotesService: Sendable {
    public let store: RecordingStore
    public init(store: RecordingStore) { self.store = store }

    /// Builds the prompt from transcript text only (no paths or device names), calls the provider, writes notities.md.
    public func generate(for recording: Recording, using provider: NotesProvider, userName: String,
                         participants: [String], template: String, title: String = "") async throws -> Recording {
        guard let transcript = store.transcriptText(for: recording), !transcript.isEmpty else { throw StoreError.transcriptMissing }
        let legend = PromptTemplate.speakerLegend(name: userName, participants: participants)
        let prompt = PromptTemplate.fill(template, name: userName, participants: participants, transcript: legend + transcript)
        do {
            let result = try await provider.generate(prompt: prompt)
            try store.writeNotes(PromptTemplate.notesDocument(body: result.text, name: userName, participants: participants,
                                                              title: title), for: recording)
            return try store.update(recording) {
                $0.notesStatus = .done; $0.notesProvider = provider.kind; $0.participants = participants
                $0.notesUsage = result.usage
            }
        } catch {
            _ = try? store.update(recording) { $0.notesStatus = .failed; $0.notesProvider = provider.kind }
            throw error
        }
    }
}
