import Foundation

public enum StoreError: Error, Equatable {
    case transcriptMissing
    case notFound
}

/// Moves files to the Trash. Abstracted so tests do not touch the real Trash.
public protocol Trasher: Sendable {
    func trash(_ url: URL) throws
}

public struct SystemTrasher: Trasher {
    public init() {}
    public func trash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
}

/// Reads and writes recording folders. The library is built by scanning, never from a cache.
public struct RecordingStore: Sendable {
    public let root: URL
    private let trasher: Trasher
    private let format: DutchFormat

    public init(root: URL, trasher: Trasher = SystemTrasher(), format: DutchFormat = DutchFormat()) {
        self.root = root; self.trasher = trasher; self.format = format
    }

    private var fm: FileManager { .default }

    /// Creates the folder (adding " 2", " 3"… if two recordings start in the same minute) and writes initial meta.
    public func create(meta: RecordingMeta) throws -> Recording {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let base = format.folderName(meta.start)
        var folder = root.appendingPathComponent(base)
        var n = 2
        while fm.fileExists(atPath: folder.path) {
            folder = root.appendingPathComponent("\(base) \(n)")
            n += 1
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let rec = Recording(folder: folder, meta: meta)
        try save(rec)
        return rec
    }

    /// Atomic write of meta.json.
    public func save(_ recording: Recording) throws {
        let data = try RecordingMeta.makeEncoder().encode(recording.meta)
        try data.write(to: recording.metaURL, options: .atomic)
    }

    public func update(_ recording: Recording, _ change: (inout RecordingMeta) -> Void) throws -> Recording {
        var r = recording
        change(&r.meta)
        try save(r)
        return r
    }

    /// All recordings, newest first. Folders without a readable meta.json are skipped.
    public func scan() -> [Recording] {
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var result: [Recording] = []
        for folder in items {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("meta.json")),
                  var meta = try? RecordingMeta.makeDecoder().decode(RecordingMeta.self, from: data) else { continue }
            // Reflect files the user moved or deleted in Finder.
            let rec = Recording(folder: folder, meta: meta)
            if !meta.audioDeleted, !fm.fileExists(atPath: rec.audioURL.path), !fm.fileExists(atPath: rec.micURL.path) {
                meta.audioDeleted = true
            }
            result.append(Recording(folder: folder, meta: meta))
        }
        return result.sorted { $0.meta.start > $1.meta.start }
    }

    public func transcriptText(for r: Recording) -> String? { try? String(contentsOf: r.transcriptURL, encoding: .utf8) }
    public func notesText(for r: Recording) -> String? { try? String(contentsOf: r.notesURL, encoding: .utf8) }

    public func hasUsableTranscript(_ r: Recording) -> Bool {
        guard let t = transcriptText(for: r) else { return false }
        return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func writeTranscript(_ text: String, for r: Recording) throws {
        try Data(text.utf8).write(to: r.transcriptURL, options: .atomic)
    }

    public func writeNotes(_ text: String, for r: Recording) throws {
        try Data(text.utf8).write(to: r.notesURL, options: .atomic)
    }

    /// Fail-safe rule: audio is only removed when a non-empty transcript is on disk, and goes to the Trash.
    public func deleteAudio(of r: Recording) throws -> Recording {
        guard hasUsableTranscript(r) else { throw StoreError.transcriptMissing }
        for url in [r.audioURL, r.micURL, r.systemURL] where fm.fileExists(atPath: url.path) {
            try trasher.trash(url)
        }
        return try update(r) { $0.audioDeleted = true }
    }

    /// Whole recording folder to the Trash.
    public func delete(_ r: Recording) throws {
        guard fm.fileExists(atPath: r.folder.path) else { throw StoreError.notFound }
        try trasher.trash(r.folder)
    }

    /// Search titles (Dutch date strings) and transcript text.
    public func search(_ recordings: [Recording], query: String) -> [Recording] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return recordings }
        return recordings.filter { r in
            let title = format.title(r.meta.start, r.meta.end) + " " + format.longTitle(r.meta.start, r.meta.end)
            if Transcript.matches(title, query: q) { return true }
            if Transcript.matches(r.meta.participants.joined(separator: " "), query: q) { return true }
            return Transcript.matches(transcriptText(for: r) ?? "", query: q)
        }
    }

    /// Recordings whose recorder never wrote an end time: a crash mid meeting.
    public func unfinishedRecordings() -> [Recording] { scan().filter { $0.meta.isUnfinished } }

    /// Closes a crashed recording using the audio that was flushed to disk.
    public func recover(_ r: Recording, audioSeconds: Double) throws -> Recording {
        try update(r) {
            $0.durationSeconds = audioSeconds
            $0.end = $0.start.addingTimeInterval(audioSeconds)
        }
    }

    /// Free bytes on the volume holding the recordings folder.
    public func freeDiskBytes() -> Int64? {
        let probe = fm.fileExists(atPath: root.path) ? root : root.deletingLastPathComponent()
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public static let lowDiskThreshold: Int64 = 2 * 1024 * 1024 * 1024
    public func isDiskLow() -> Bool { (freeDiskBytes() ?? .max) < Self.lowDiskThreshold }

    public static let minimumRecordingSeconds: Double = 10
}

public struct RecentBadge: Equatable, Sendable {
    public enum Kind: Sendable { case notes, transcript, failed }
    public let kind: Kind

    public init?(for r: Recording) {
        if r.meta.transcriptStatus == .failed { kind = .failed }
        else if r.hasNotes { kind = .notes }
        else if r.hasTranscript { kind = .transcript }
        else { return nil }
    }
}
