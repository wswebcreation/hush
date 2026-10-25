import AppKit
import HushCore
import os

private let log = Logger(subsystem: "nl.techchamps.hush", category: "flow")

/// State for one recording's post recording window. Outlives the window so transcription can run in the background.
@MainActor
final class FlowModel: ObservableObject {
    @Published var recording: Recording
    @Published var flow: PostRecordingFlow
    @Published var progress: Double = 0
    @Published var secondsLeft: Double?
    @Published var transcript = ""
    @Published var choice: NotesChoice
    @Published var participants: [String]
    @Published var notes = ""
    @Published var deleteAudio: Bool
    @Published private(set) var isBusy = false
    @Published private(set) var failureProvider: NotesProviderKind?

    unowned let app: AppModel
    private var task: Task<Void, Never>?
    private var startedTranscribing: Date?
    private(set) var inBackground = false

    init(recording: Recording, app: AppModel) {
        self.recording = recording
        self.app = app
        let s = app.settings
        flow = PostRecordingFlow(step: recording.meta.transcriptStatus == .done ? .review : .transcribe)
        choice = .provider(s.lastProvider)
        participants = recording.meta.participants
        deleteAudio = s.deleteAudioByDefault
        if recording.meta.transcriptStatus == .done { transcript = app.store.transcriptText(for: recording) ?? "" }
    }

    var store: RecordingStore { app.store }
    var segments: [TranscriptSegment] { Transcript.parse(transcript) }
    var title: String { app.format.title(recording.meta.start, recording.meta.end) }
    var longDateLine: String { app.format.title(recording.meta.start, recording.meta.end) }
    var transcriptUsable: Bool { store.hasUsableTranscript(recording) }
    var hasNotes: Bool { recording.meta.notesStatus == .done }
    var displayFolder: String { recording.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }

    // MARK: Step 1 · transcribing

    func startTranscription() {
        guard !isBusy else { return }
        isBusy = true
        flow.retryTranscription()
        progress = 0; secondsLeft = nil
        startedTranscribing = Date()
        let rec = recording
        let store = self.store
        let locale = app.settings.transcriptionLocale
        let hasSystem = rec.meta.systemAudioCaptured && FileManager.default.fileExists(atPath: rec.systemURL.path)

        task = Task { [weak self] in
            do {
                _ = try? store.update(rec) { $0.transcriptStatus = .inProgress }
                async let mix: Void = (try? await AudioMixer.export(mic: rec.micURL, system: hasSystem ? rec.systemURL : nil, to: rec.audioURL)) ?? ()

                let progressBox = ProgressBox(passes: hasSystem ? 2 : 1)
                let report: @Sendable (Int, Double) -> Void = { pass, value in
                    let total = progressBox.set(pass: pass, value: value)
                    Task { @MainActor in self?.updateProgress(total) }
                }
                let micSegments = try await Transcriber.transcribe(file: rec.micURL, speaker: .you, locale: locale) { report(0, $0) }
                var systemSegments: [TranscriptSegment] = []
                if hasSystem {
                    systemSegments = try await Transcriber.transcribe(file: rec.systemURL, speaker: .them, locale: locale) { report(1, $0) }
                }
                _ = await mix
                try Task.checkCancellation()
                let merged = Transcript.merge(mic: micSegments, system: systemSegments)
                guard !merged.isEmpty else { throw TranscriberError.empty }
                let text = Transcript.render(merged)
                try store.writeTranscript(text, for: rec)
                let updated = try store.update(rec) { $0.transcriptStatus = .done }
                await self?.transcriptionSucceeded(updated, text: text)
            } catch is CancellationError {
                await self?.transcriptionCancelled()
            } catch {
                log.error("transcription failed: \(String(describing: error))")
                await self?.transcriptionFailed()
            }
        }
    }

    private func updateProgress(_ value: Double) {
        progress = max(progress, value)
        if let started = startedTranscribing, progress > 0.05 {
            let spent = Date().timeIntervalSince(started)
            secondsLeft = spent / progress * (1 - progress)
        }
    }

    private func transcriptionSucceeded(_ updated: Recording, text: String) {
        recording = updated
        transcript = text
        isBusy = false
        progress = 1
        app.reloadRecordings()
        flow.transcriptionFinished()
        if inBackground {
            inBackground = false
            app.notify(title: L10n.notificationDoneTitle, body: L10n.notificationDoneBody, identifier: "done-\(updated.id)")
        }
    }

    private func transcriptionFailed() {
        isBusy = false
        recording = (try? store.update(recording) { $0.transcriptStatus = .failed }) ?? recording
        app.reloadRecordings()
        flow.transcriptionFailed()
    }

    private func transcriptionCancelled() {
        isBusy = false
        recording = (try? store.update(recording) { $0.transcriptStatus = .failed }) ?? recording
        app.reloadRecordings()
    }

    /// Annuleer: stop transcribing, keep audio, close.
    func cancelTranscription() {
        task?.cancel()
        app.windows.closeFlow(recording.id)
        app.flowFinished(recording.id)
    }

    /// Op de achtergrond: close the window but keep transcribing.
    func moveToBackground() {
        inBackground = true
        app.windows.closeFlow(recording.id)
    }

    // MARK: Step 3 · notes

    func hasKey(_ kind: NotesProviderKind) -> Bool { app.secrets.hasKey(for: kind) }
    var canSubmit: Bool { PostRecordingFlow.canSubmit(choice, hasKey: hasKey) }

    func addParticipant(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !participants.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        participants.append(name)
    }

    func submitNotes() {
        switch choice {
        case .skip:
            persistParticipants()
            flow.submitNotes(.skip)
        case .provider(let kind):
            app.settings.lastProvider = kind
            persistParticipants()
            flow.submitNotes(choice)
            generateNotes(with: kind)
        }
    }

    private func persistParticipants() {
        app.settings.rememberParticipants(participants)
        recording = (try? store.update(recording) { $0.participants = self.participants }) ?? recording
    }

    func generateNotes(with kind: NotesProviderKind) {
        guard !isBusy else { return }
        isBusy = true
        failureProvider = nil
        flow.retryNotes()
        let rec = recording
        let provider = app.notesProvider(for: kind)
        let service = NotesService(store: store)
        let name = app.settings.userName, people = participants, template = app.settings.promptTemplate, title = self.title
        task = Task { [weak self] in
            do {
                let updated = try await service.generate(for: rec, using: provider, userName: name, participants: people, template: template, title: title)
                let text = service.store.notesText(for: updated) ?? ""
                try? DocxExporter.write(markdown: text, to: updated.notesDocxURL)
                await MainActor.run {
                    guard let self else { return }
                    self.recording = updated; self.notes = text; self.isBusy = false
                    self.app.reloadRecordings()
                    self.flow.notesDone()
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.isBusy = false
                    self.failureProvider = kind
                    self.recording = self.store.scan().first { $0.id == rec.id } ?? self.recording
                    self.app.reloadRecordings()
                    self.flow.notesFailed()
                }
            }
        }
    }

    var currentProvider: NotesProviderKind {
        if case .provider(let p) = choice { return p }
        return failureProvider ?? app.settings.lastProvider
    }

    func retryNotes() { generateNotes(with: failureProvider ?? currentProvider) }
    func switchProvider() {
        let other = (failureProvider ?? currentProvider).other
        choice = .provider(other)
        guard hasKey(other) else { return }
        app.settings.lastProvider = other
        generateNotes(with: other)
    }
    func skipNotes() { flow.continueToFinish() }

    func loadNotes() {
        if notes.isEmpty { notes = store.notesText(for: recording) ?? "" }
    }

    // MARK: Step 5 · finishing

    func finish(openLibrary: Bool, closedViaWindowButton: Bool = false) {
        var rec = recording
        if AudioDeletionPolicy.shouldDelete(checkboxOn: deleteAudio, transcriptUsable: transcriptUsable,
                                            closedViaWindowButton: closedViaWindowButton) {
            rec = (try? store.deleteAudio(of: rec)) ?? rec
        }
        app.flowFinished(rec.id)
        app.windows.closeFlow(rec.id, force: true)
        if openLibrary { app.openInLibrary(rec.id) }
    }

    func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
    func copyNotes() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notes, forType: .string)
    }
    func reveal() { app.reveal(recording) }
    func openNotesFile() {
        if let url = DocxExporter.ensureDocument(for: recording) { NSWorkspace.shared.open(url) }
    }
}

/// Combines per-pass progress into one overall fraction. Called from transcription tasks.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double]
    init(passes: Int) { values = Array(repeating: 0, count: passes) }
    func set(pass: Int, value: Double) -> Double {
        lock.withLock {
            values[pass] = value
            return values.reduce(0, +) / Double(values.count)
        }
    }
}
