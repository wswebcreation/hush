import Foundation
@testable import HushCore

final class RecordingTrasher: Trasher, @unchecked Sendable {
    var trashed: [URL] = []
    func trash(_ url: URL) throws {
        trashed.append(url)
        try FileManager.default.removeItem(at: url)
    }
}

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("hush-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Fixed calendar so tests do not depend on the machine's time zone.
func amsterdamFormat() -> DutchFormat {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    return DutchFormat(calendar: c)
}

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

struct StubClient: HTTPClient {
    let responses: ResponseQueue
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await responses.next(request)
    }
}

actor ResponseQueue {
    var items: [Result<(Int, String), Error>]
    private(set) var requests: [URLRequest] = []
    init(_ items: [Result<(Int, String), Error>]) { self.items = items }
    func next(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let item = items.isEmpty ? .success((200, "{}")) : items.removeFirst()
        let (status, body) = try item.get()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

struct FakeProvider: NotesProvider {
    let kind: NotesProviderKind
    var result: Result<String, Error>
    func generate(prompt: String) async throws -> NotesResult {
        NotesResult(text: try result.get(), usage: NotesUsage(model: "claude-sonnet-5-5", inputTokens: 1000, outputTokens: 500))
    }
    func testKey() async -> Bool { true }
}
