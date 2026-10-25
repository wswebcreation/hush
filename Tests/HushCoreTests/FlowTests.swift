import Testing
import Foundation
@testable import HushCore

@Suite struct PostRecordingFlowTests {
    @Test func stepStates() {
        var flow = PostRecordingFlow()
        #expect(flow.state(of: .transcribe) == .current)
        #expect(flow.state(of: .review) == .upcoming)
        flow.transcriptionFinished()
        #expect(flow.state(of: .transcribe) == .completed)
        #expect(flow.state(of: .review) == .current)
    }

    @Test func transcriptionFailureMarksStepOneFailed() {
        var flow = PostRecordingFlow()
        flow.transcriptionFailed()
        #expect(flow.state(of: .transcribe) == .failed)
        flow.retryTranscription()
        #expect(flow.state(of: .transcribe) == .current)
    }

    @Test func backOnlyOnReviewAndNotes() {
        var flow = PostRecordingFlow()
        #expect(!flow.canGoBack)
        flow.transcriptionFinished(); #expect(flow.canGoBack)
        flow.reviewDone(); #expect(flow.canGoBack)
        flow.back(); #expect(flow.step == .review)
        flow.reviewDone()
        flow.submitNotes(.provider(.claude))
        #expect(flow.step == .generate)
        #expect(!flow.canGoBack)
        flow.back(); #expect(flow.step == .generate)
    }

    @Test func skipGoesStraightToFinish() {
        var flow = PostRecordingFlow(step: .notes)
        flow.submitNotes(.skip)
        #expect(flow.step == .finish)
        #expect(!flow.notesSent)
    }

    @Test func notesFailureAndRetry() {
        var flow = PostRecordingFlow(step: .notes)
        flow.submitNotes(.provider(.openai))
        flow.notesFailed()
        #expect(flow.state(of: .generate) == .failed)
        #expect(flow.state(of: .notes) == .completed)
        flow.retryNotes()
        #expect(flow.state(of: .generate) == .current)
        flow.continueToFinish()
        #expect(flow.step == .finish)
    }

    @Test func submitRequiresKeyForProviders() {
        let hasClaudeOnly: (NotesProviderKind) -> Bool = { $0 == .claude }
        #expect(PostRecordingFlow.canSubmit(.provider(.claude), hasKey: hasClaudeOnly))
        #expect(!PostRecordingFlow.canSubmit(.provider(.openai), hasKey: hasClaudeOnly))
        #expect(PostRecordingFlow.canSubmit(.skip, hasKey: { _ in false }))
    }

    @Test func labelsAndNoticesFollowChoice() {
        #expect(PostRecordingFlow.sendLabel(.provider(.claude)) == "Stuur naar Claude")
        #expect(PostRecordingFlow.sendLabel(.provider(.openai)) == "Stuur naar ChatGPT")
        #expect(PostRecordingFlow.sendLabel(.skip) == "Ga door zonder notities")
        #expect(PostRecordingFlow.notice(.provider(.openai)).contains("OpenAI"))
        #expect(PostRecordingFlow.notice(.skip).hasPrefix("Er wordt niets verstuurd"))
    }

    @Test func providerOtherFlips() {
        #expect(NotesProviderKind.claude.other == .openai)
        #expect(NotesProviderKind.openai.other.displayName == "Claude")
    }

    @Test func audioDeletionPolicy() {
        #expect(AudioDeletionPolicy.initialChoice(settingDefault: true, transcriptUsable: true))
        #expect(!AudioDeletionPolicy.initialChoice(settingDefault: true, transcriptUsable: false))
        #expect(!AudioDeletionPolicy.initialChoice(settingDefault: false, transcriptUsable: true))
        #expect(AudioDeletionPolicy.shouldDelete(checkboxOn: true, transcriptUsable: true, closedViaWindowButton: false))
        #expect(!AudioDeletionPolicy.shouldDelete(checkboxOn: true, transcriptUsable: true, closedViaWindowButton: true))
        #expect(!AudioDeletionPolicy.shouldDelete(checkboxOn: true, transcriptUsable: false, closedViaWindowButton: false))
    }
}

@Suite struct NotesServiceTests {
    func setup() throws -> (NotesService, RecordingStore, Recording) {
        let store = RecordingStore(root: makeTempDir(), trasher: RecordingTrasher(), format: amsterdamFormat())
        let rec = try store.create(meta: RecordingMeta(start: date(2026, 10, 21, 14), end: date(2026, 10, 21, 14, 45)))
        try store.writeTranscript("[00:00:01] Jij: hoi", for: rec)
        return (NotesService(store: store), store, rec)
    }

    @Test func successWritesNotesAndMeta() async throws {
        let (service, store, rec) = try setup()
        let updated = try await service.generate(for: rec, using: FakeProvider(kind: .claude, result: .success("# Notities")),
                                                 userName: "Wim", participants: ["Sanne"], template: "{transcript}")
        #expect(updated.meta.notesStatus == .done)
        #expect(updated.meta.notesProvider == .claude)
        #expect(updated.meta.participants == ["Sanne"])
        #expect(store.notesText(for: rec) == "**Deelnemers:** Wim, Sanne\n\n# Notities")
        #expect(updated.meta.notesUsage?.totalTokens == 1500)
        // $2 / $10 per million tokens: 1000 in + 500 out
        #expect(abs((updated.meta.notesUsage?.costUSD ?? 0) - 0.007) < 1e-9)
    }

    @Test func promptTellsTheModelWhoIsWho() {
        let legend = PromptTemplate.speakerLegend(name: "Wim", participants: ["Sanne"])
        #expect(legend.contains("\"Jij\" is Wim"))
        #expect(legend.contains("\"Anderen\" is Sanne"))
    }

    @Test func unknownModelHasTokensButNoCost() {
        #expect(NotesUsage(model: "mystery", inputTokens: 1, outputTokens: 1).costUSD == nil)
    }

    @Test func failureKeepsTranscriptAndMarksFailed() async throws {
        let (service, store, rec) = try setup()
        await #expect(throws: NotesError.http(500)) {
            _ = try await service.generate(for: rec, using: FakeProvider(kind: .openai, result: .failure(NotesError.http(500))),
                                           userName: "Wim", participants: [], template: "{transcript}")
        }
        #expect(store.hasUsableTranscript(rec))
        #expect(store.scan()[0].meta.notesStatus == .failed)
        #expect(store.notesText(for: rec) == nil)
    }

    @Test func missingTranscriptThrowsBeforeAnyRequest() async throws {
        let store = RecordingStore(root: makeTempDir(), trasher: RecordingTrasher())
        let rec = try store.create(meta: RecordingMeta(start: Date()))
        await #expect(throws: StoreError.transcriptMissing) {
            _ = try await NotesService(store: store).generate(for: rec, using: FakeProvider(kind: .claude, result: .success("x")),
                                                              userName: "", participants: [], template: "")
        }
    }
}
