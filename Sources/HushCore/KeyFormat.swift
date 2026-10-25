import Foundation

/// Cheap sanity check on pasted API keys, so a stray clipboard is never saved as a key.
public enum KeyFormat {
    public static func clean(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func looksValid(_ raw: String, for provider: NotesProviderKind) -> Bool {
        let key = clean(raw)
        guard key.count >= 20, key.count <= 300, key.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        switch provider {
        case .claude: return key.hasPrefix("sk-ant-")
        case .openai: return key.hasPrefix("sk-") && !key.hasPrefix("sk-ant-")
        }
    }
}

extension NotesProviderKind {
    /// Page where the user creates an API key.
    public var keyPageURL: URL {
        switch self {
        case .claude: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        }
    }
    public var keyPageHost: String { keyPageURL.host ?? "" }
    public var keyPrefixHint: String { self == .claude ? "sk-ant-…" : "sk-…" }
}
