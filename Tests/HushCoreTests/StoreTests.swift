import Testing
import Foundation
@testable import HushCore

@Suite struct RecordingStoreTests {
    func makeStore() -> (RecordingStore, RecordingTrasher, URL) {
        let root = makeTempDir()
        let trasher = RecordingTrasher()
        return (RecordingStore(root: root, trasher: trasher, format: amsterdamFormat()), trasher, root)
    }

    func meta(_ start: Date, end: Date? = nil) -> RecordingMeta {
        RecordingMeta(start: start, end: end, durationSeconds: 60)
    }

    @Test func createWritesFolderAndMeta() throws {
        let (store, _, _) = makeStore()
        let rec = try store.create(meta: meta(date(2026, 10, 21, 14)))
        #expect(rec.folder.lastPathComponent == "2026-10-21 14.00")
        #expect(FileManager.default.fileExists(atPath: rec.metaURL.path))
    }

    @Test func createAvoidsFolderCollisions() throws {
        let (store, _, _) = makeStore()
        let a = try store.create(meta: meta(date(2026, 10, 21, 14)))
        let b = try store.create(meta: meta(date(2026, 10, 21, 14)))
        #expect(a.folder != b.folder)
        #expect(b.folder.lastPathComponent == "2026-10-21 14.00 2")
    }

    @Test func scanReturnsNewestFirstAndSkipsJunk() throws {
        let (store, _, root) = makeStore()
        _ = try store.create(meta: meta(date(2026, 10, 20, 9)))
        _ = try store.create(meta: meta(date(2026, 10, 21, 9)))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("zonder meta"), withIntermediateDirectories: true)
        let found = store.scan()
        #expect(found.count == 2)
        #expect(found[0].meta.start > found[1].meta.start)
    }

    @Test func scanReflectsAudioRemovedInFinder() throws {
        let (store, _, _) = makeStore()
        let rec = try store.create(meta: meta(date(2026, 10, 21, 9)))
        #expect(store.scan()[0].meta.audioDeleted)  // no audio file present
        try Data("x".utf8).write(to: rec.audioURL)
        #expect(!store.scan()[0].meta.audioDeleted)
    }

    @Test func deleteAudioRefusesWithoutTranscript() throws {
        let (store, trasher, _) = makeStore()
        let rec = try store.create(meta: meta(date(2026, 10, 21, 9)))
        try Data("a".utf8).write(to: rec.audioURL)
        #expect(throws: StoreError.transcriptMissing) { try store.deleteAudio(of: rec) }
        try store.writeTranscript("   \n", for: rec)
        #expect(throws: StoreError.transcriptMissing) { try store.deleteAudio(of: rec) }
        #expect(trasher.trashed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: rec.audioURL.path))
    }

    @Test func deleteAudioTrashesAudioFilesAndKeepsTranscript() throws {
        let (store, trasher, _) = makeStore()
        let rec = try store.create(meta: meta(date(2026, 10, 21, 9)))
        for u in [rec.audioURL, rec.micURL, rec.systemURL] { try Data("a".utf8).write(to: u) }
        try store.writeTranscript("[00:00:01] Jij: hoi", for: rec)
        let updated = try store.deleteAudio(of: rec)
        #expect(updated.meta.audioDeleted)
        #expect(trasher.trashed.count == 3)
        #expect(FileManager.default.fileExists(atPath: rec.transcriptURL.path))
    }

    @Test func deleteRecordingTrashesWholeFolder() throws {
        let (store, trasher, _) = makeStore()
        let rec = try store.create(meta: meta(date(2026, 10, 21, 9)))
        try store.delete(rec)
        #expect(trasher.trashed == [rec.folder])
        #expect(store.scan().isEmpty)
    }

    @Test func searchMatchesTranscriptTitleAndParticipants() throws {
        let (store, _, _) = makeStore()
        var m = meta(date(2026, 10, 21, 14), end: date(2026, 10, 21, 14, 45))
        m.participants = ["Sanne de Vries"]
        let a = try store.create(meta: m)
        try store.writeTranscript("[00:00:01] Jij: regressiesuite", for: a)
        let b = try store.create(meta: meta(date(2026, 10, 19, 9)))
        let all = [a, b]
        #expect(store.search(all, query: "regressie").map(\.id) == [a.id])
        #expect(store.search(all, query: "sanne").map(\.id) == [a.id])
        #expect(store.search(all, query: "21 okt").map(\.id) == [a.id])
        #expect(store.search(all, query: "").count == 2)
    }

    @Test func unfinishedRecordingsAreDetectedAndRecovered() throws {
        let (store, _, _) = makeStore()
        let rec = try store.create(meta: meta(date(2026, 10, 21, 14)))
        #expect(store.unfinishedRecordings().count == 1)
        let fixed = try store.recover(rec, audioSeconds: 32 * 60)
        #expect(fixed.meta.end == date(2026, 10, 21, 14, 32))
        #expect(store.unfinishedRecordings().isEmpty)
    }

    @Test func recentBadgePriority() {
        var m = meta(date(2026, 10, 21, 9))
        let f = URL(fileURLWithPath: "/tmp/x")
        #expect(RecentBadge(for: Recording(folder: f, meta: m)) == nil)
        m.transcriptStatus = .done
        #expect(RecentBadge(for: Recording(folder: f, meta: m))?.kind == .transcript)
        m.notesStatus = .done
        #expect(RecentBadge(for: Recording(folder: f, meta: m))?.kind == .notes)
        m.transcriptStatus = .failed
        #expect(RecentBadge(for: Recording(folder: f, meta: m))?.kind == .failed)
    }

    @Test func metaJSONRoundTrip() throws {
        let m = RecordingMeta(start: date(2026, 10, 21, 14), end: date(2026, 10, 21, 14, 45), participants: ["A"], notesProvider: .claude)
        let data = try RecordingMeta.makeEncoder().encode(m)
        #expect(try RecordingMeta.makeDecoder().decode(RecordingMeta.self, from: data) == m)
        #expect(String(data: data, encoding: .utf8)!.contains("\"transcriptStatus\""))
    }
}
