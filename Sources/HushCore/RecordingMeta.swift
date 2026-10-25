import Foundation

public enum TranscriptStatus: String, Codable, Sendable { case none, inProgress, done, failed }
public enum NotesStatus: String, Codable, Sendable { case none, done, failed }
public enum NotesProviderKind: String, Codable, Sendable, CaseIterable {
    case claude, openai

    public var displayName: String { self == .claude ? "Claude" : "ChatGPT" }
    public var company: String { self == .claude ? "Anthropic" : "OpenAI" }
    public var other: NotesProviderKind { self == .claude ? .openai : .claude }
}

/// Contents of `meta.json`. `end == nil` means the recording never finished (crash).
public struct RecordingMeta: Codable, Equatable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date?
    public var durationSeconds: Double
    public var micDevice: String
    public var systemAudioCaptured: Bool
    public var participants: [String]
    public var transcriptStatus: TranscriptStatus
    public var notesProvider: NotesProviderKind?
    public var notesStatus: NotesStatus
    public var audioDeleted: Bool
    public var appVersion: String
    /// Tokens and estimated cost of the last notes request. Nil for older recordings or when notes were skipped.
    public var notesUsage: NotesUsage?

    public init(
        id: UUID = UUID(), start: Date, end: Date? = nil, durationSeconds: Double = 0,
        micDevice: String = "", systemAudioCaptured: Bool = true, participants: [String] = [],
        transcriptStatus: TranscriptStatus = .none, notesProvider: NotesProviderKind? = nil,
        notesStatus: NotesStatus = .none, audioDeleted: Bool = false, appVersion: String = "1.0",
        notesUsage: NotesUsage? = nil
    ) {
        self.id = id; self.start = start; self.end = end; self.durationSeconds = durationSeconds
        self.micDevice = micDevice; self.systemAudioCaptured = systemAudioCaptured
        self.participants = participants; self.transcriptStatus = transcriptStatus
        self.notesProvider = notesProvider; self.notesStatus = notesStatus
        self.audioDeleted = audioDeleted; self.appVersion = appVersion; self.notesUsage = notesUsage
    }

    public var isUnfinished: Bool { end == nil }

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// A recording on disk: its folder plus parsed metadata.
public struct Recording: Identifiable, Equatable, Sendable {
    public var folder: URL
    public var meta: RecordingMeta
    public var id: UUID { meta.id }

    public init(folder: URL, meta: RecordingMeta) { self.folder = folder; self.meta = meta }

    public var transcriptURL: URL { folder.appendingPathComponent("transcript.txt") }
    public var notesURL: URL { folder.appendingPathComponent("notities.md") }
    public var notesDocxURL: URL { folder.appendingPathComponent("notities.docx") }
    public var audioURL: URL { folder.appendingPathComponent("audio.m4a") }
    public var micURL: URL { folder.appendingPathComponent("mic.caf") }
    public var systemURL: URL { folder.appendingPathComponent("system.caf") }
    public var metaURL: URL { folder.appendingPathComponent("meta.json") }

    public var hasTranscript: Bool { meta.transcriptStatus == .done }
    public var hasNotes: Bool { meta.notesStatus == .done }
}
