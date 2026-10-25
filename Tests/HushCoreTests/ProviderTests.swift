import Testing
import Foundation
@testable import HushCore

@Suite struct ProviderTests {
    func secrets(_ kind: NotesProviderKind, key: String = "sk-test") -> InMemorySecretStore {
        let s = InMemorySecretStore(); try! s.write(key, account: kind.keychainAccount); return s
    }
    let fast = RetryPolicy(maxRetries: 1, backoff: .milliseconds(1))
    let claudeOK = #"{"content":[{"type":"text","text":"Notities"}]}"#
    let openAIOK = #"{"choices":[{"message":{"content":"Notities"}}]}"#

    @Test func claudeBuildsRequestWithHeadersAndTranscriptOnly() async throws {
        let queue = ResponseQueue([.success((200, claudeOK))])
        let p = ClaudeProvider(secrets: secrets(.claude), model: "", client: StubClient(responses: queue), retry: fast)
        let text = try await p.generateNotes(prompt: "PROMPT")
        #expect(text == "Notities")
        let req = await queue.requests[0]
        #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(req.timeoutInterval == 120)
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        #expect(body["model"] as? String == ClaudeProvider.defaultModel)
        #expect((body["messages"] as! [[String: String]])[0]["content"] == "PROMPT")
    }

    @Test func openAIBuildsBearerRequest() async throws {
        let queue = ResponseQueue([.success((200, openAIOK))])
        let p = OpenAIProvider(secrets: secrets(.openai), model: "gpt-x", client: StubClient(responses: queue), retry: fast)
        #expect(try await p.generateNotes(prompt: "P") == "Notities")
        let req = await queue.requests[0]
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        #expect(body["model"] as? String == "gpt-x")
    }

    @Test func missingKeyThrowsWithoutNetworkCall() async {
        let queue = ResponseQueue([])
        let p = ClaudeProvider(secrets: InMemorySecretStore(), client: StubClient(responses: queue), retry: fast)
        await #expect(throws: NotesError.missingKey) { _ = try await p.generateNotes(prompt: "x") }
        #expect(await queue.requests.isEmpty)
    }

    @Test func retriesOnceOn429ThenSucceeds() async throws {
        let queue = ResponseQueue([.success((429, "{}")), .success((200, claudeOK))])
        let p = ClaudeProvider(secrets: secrets(.claude), client: StubClient(responses: queue), retry: fast)
        #expect(try await p.generateNotes(prompt: "x") == "Notities")
        #expect(await queue.requests.count == 2)
    }

    @Test func retriesOnlyOnceOn5xx() async {
        let queue = ResponseQueue([.success((503, "{}")), .success((503, "{}")), .success((200, claudeOK))])
        let p = ClaudeProvider(secrets: secrets(.claude), client: StubClient(responses: queue), retry: fast)
        await #expect(throws: NotesError.http(503)) { _ = try await p.generateNotes(prompt: "x") }
        #expect(await queue.requests.count == 2)
    }

    @Test func doesNotRetryOn401() async {
        let queue = ResponseQueue([.success((401, "{}"))])
        let p = OpenAIProvider(secrets: secrets(.openai), client: StubClient(responses: queue), retry: fast)
        await #expect(throws: NotesError.http(401)) { _ = try await p.generateNotes(prompt: "x") }
        #expect(await queue.requests.count == 1)
    }

    @Test func networkErrorBecomesNetwork() async {
        let queue = ResponseQueue([.failure(URLError(.notConnectedToInternet)), .failure(URLError(.notConnectedToInternet))])
        let p = ClaudeProvider(secrets: secrets(.claude), client: StubClient(responses: queue), retry: fast)
        await #expect(throws: NotesError.network) { _ = try await p.generateNotes(prompt: "x") }
    }

    @Test func emptyResponseIsAnError() async {
        let queue = ResponseQueue([.success((200, #"{"content":[]}"#))])
        let p = ClaudeProvider(secrets: secrets(.claude), client: StubClient(responses: queue), retry: fast)
        await #expect(throws: NotesError.emptyResponse) { _ = try await p.generateNotes(prompt: "x") }
    }

    @Test func testKeyReflectsStatus() async {
        let good = ClaudeProvider(secrets: secrets(.claude), client: StubClient(responses: ResponseQueue([.success((200, claudeOK))])))
        let bad = OpenAIProvider(secrets: secrets(.openai), client: StubClient(responses: ResponseQueue([.success((401, "{}"))])))
        #expect(await good.testKey())
        #expect(!(await bad.testKey()))
    }

    @Test func secretStoreHasKey() throws {
        let s = InMemorySecretStore()
        #expect(!s.hasKey(for: .claude))
        try s.write("k", account: NotesProviderKind.claude.keychainAccount)
        #expect(s.hasKey(for: .claude))
        s.delete(account: NotesProviderKind.claude.keychainAccount)
        #expect(!s.hasKey(for: .claude))
    }
}
