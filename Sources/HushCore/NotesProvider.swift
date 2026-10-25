import Foundation

public protocol NotesProvider: Sendable {
    var kind: NotesProviderKind { get }
    func generate(prompt: String) async throws -> NotesResult
    /// Tiny request used by the Test button.
    func testKey() async -> Bool
}

public extension NotesProvider {
    func generateNotes(prompt: String) async throws -> String { try await generate(prompt: prompt).text }
}

public enum NotesError: Error, Equatable {
    case missingKey
    case http(Int)
    case emptyResponse
    case network
}

/// Abstraction over URLSession so providers can be tested without a network.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionClient: HTTPClient {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NotesError.network }
        return (data, http)
    }
}

public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var backoff: Duration
    public init(maxRetries: Int = 1, backoff: Duration = .seconds(2)) { self.maxRetries = maxRetries; self.backoff = backoff }
    public static let none = RetryPolicy(maxRetries: 0, backoff: .zero)
}

/// Shared request/retry plumbing: 120 s timeout, one retry on 429 / 5xx.
struct RequestRunner {
    let client: HTTPClient
    let retry: RetryPolicy

    func run(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await client.send(request)
                if (200..<300).contains(response.statusCode) { return data }
                let retriable = response.statusCode == 429 || response.statusCode >= 500
                if retriable && attempt < retry.maxRetries {
                    attempt += 1
                    try await Task.sleep(for: retry.backoff * attempt)
                    continue
                }
                throw NotesError.http(response.statusCode)
            } catch let error as NotesError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt < retry.maxRetries {
                    attempt += 1
                    try await Task.sleep(for: retry.backoff * attempt)
                    continue
                }
                throw NotesError.network
            }
        }
    }
}

public struct ClaudeProvider: NotesProvider {
    public static let defaultModel = "claude-sonnet-5-5"
    public static let knownModels = ["claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
    public let kind = NotesProviderKind.claude
    let secrets: SecretStore
    let model: String
    let client: HTTPClient
    let retry: RetryPolicy

    public init(secrets: SecretStore, model: String? = nil, client: HTTPClient = URLSessionClient(), retry: RetryPolicy = .init()) {
        self.secrets = secrets
        self.model = (model?.isEmpty == false) ? model! : Self.defaultModel
        self.client = client
        self.retry = retry
    }

    func makeRequest(prompt: String, maxTokens: Int) throws -> URLRequest {
        guard let key = secrets.read(account: kind.keychainAccount), !key.isEmpty else { throw NotesError.missingKey }
        var r = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 120)
        r.httpMethod = "POST"
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model, "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    public func generate(prompt: String) async throws -> NotesResult {
        let data = try await RequestRunner(client: client, retry: retry).run(makeRequest(prompt: prompt, maxTokens: 4096))
        struct Response: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            struct Usage: Decodable { let input_tokens: Int?; let output_tokens: Int? }
            let content: [Block]; let usage: Usage?
        }
        let decoded = try? JSONDecoder().decode(Response.self, from: data)
        let text = decoded?.content.compactMap { $0.type == "text" ? $0.text : nil }.joined() ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NotesError.emptyResponse }
        return NotesResult(text: text, usage: NotesUsage(model: model, inputTokens: decoded?.usage?.input_tokens ?? 0,
                                                         outputTokens: decoded?.usage?.output_tokens ?? 0))
    }

    public func testKey() async -> Bool {
        guard let r = try? makeRequest(prompt: "Antwoord met: ok", maxTokens: 8) else { return false }
        return (try? await RequestRunner(client: client, retry: .none).run(r)) != nil
    }
}

public struct OpenAIProvider: NotesProvider {
    public static let defaultModel = "gpt-5"
    public let kind = NotesProviderKind.openai
    let secrets: SecretStore
    let model: String
    let client: HTTPClient
    let retry: RetryPolicy

    public init(secrets: SecretStore, model: String? = nil, client: HTTPClient = URLSessionClient(), retry: RetryPolicy = .init()) {
        self.secrets = secrets
        self.model = (model?.isEmpty == false) ? model! : Self.defaultModel
        self.client = client
        self.retry = retry
    }

    func makeRequest(prompt: String) throws -> URLRequest {
        guard let key = secrets.read(account: kind.keychainAccount), !key.isEmpty else { throw NotesError.missingKey }
        var r = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!, timeoutInterval: 120)
        r.httpMethod = "POST"
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = ["model": model, "messages": [["role": "user", "content": prompt]]]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    public func generate(prompt: String) async throws -> NotesResult {
        let data = try await RequestRunner(client: client, retry: retry).run(makeRequest(prompt: prompt))
        struct Response: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
            struct Usage: Decodable { let prompt_tokens: Int?; let completion_tokens: Int? }
            let choices: [Choice]; let usage: Usage?
        }
        let decoded = try? JSONDecoder().decode(Response.self, from: data)
        let text = decoded?.choices.first?.message.content ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NotesError.emptyResponse }
        return NotesResult(text: text, usage: NotesUsage(model: model, inputTokens: decoded?.usage?.prompt_tokens ?? 0,
                                                         outputTokens: decoded?.usage?.completion_tokens ?? 0))
    }

    public func testKey() async -> Bool {
        guard let r = try? makeRequest(prompt: "Antwoord met: ok") else { return false }
        return (try? await RequestRunner(client: client, retry: .none).run(r)) != nil
    }
}
