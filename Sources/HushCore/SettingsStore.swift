import Foundation

/// User defaults wrapper. Never stores API keys (those live in the Keychain).
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }

    public var userName: String {
        get { defaults.string(forKey: "userName") ?? NSFullUserName().split(separator: " ").first.map(String.init) ?? "" }
        set { defaults.set(newValue, forKey: "userName") }
    }
    public var launchAtLogin: Bool { get { bool("launchAtLogin", default: true) } set { defaults.set(newValue, forKey: "launchAtLogin") } }
    public var showInDock: Bool { get { bool("showInDock", default: false) } set { defaults.set(newValue, forKey: "showInDock") } }
    public var captureSystemAudio: Bool { get { bool("captureSystemAudio", default: true) } set { defaults.set(newValue, forKey: "captureSystemAudio") } }
    public var deleteAudioByDefault: Bool { get { bool("deleteAudioByDefault", default: true) } set { defaults.set(newValue, forKey: "deleteAudioByDefault") } }
    public var micDeviceUID: String? { get { defaults.string(forKey: "micDeviceUID") } set { defaults.set(newValue, forKey: "micDeviceUID") } }
    public var hasSeenHelp: Bool { get { defaults.bool(forKey: "hasSeenHelp") } set { defaults.set(newValue, forKey: "hasSeenHelp") } }
    public var hasCompletedOnboarding: Bool { get { defaults.bool(forKey: "hasCompletedOnboarding") } set { defaults.set(newValue, forKey: "hasCompletedOnboarding") } }
    /// The app version whose intro and release notes were last shown.
    public var lastSeenVersion: String? { get { defaults.string(forKey: "lastSeenVersion") } set { defaults.set(newValue, forKey: "lastSeenVersion") } }
    public var lastProvider: NotesProviderKind { get { NotesProviderKind(rawValue: defaults.string(forKey: "lastProvider") ?? "") ?? .claude } set { defaults.set(newValue.rawValue, forKey: "lastProvider") } }
    public var claudeModel: String { get { defaults.string(forKey: "claudeModel") ?? "" } set { defaults.set(newValue, forKey: "claudeModel") } }
    public var openAIModel: String { get { defaults.string(forKey: "openAIModel") ?? "" } set { defaults.set(newValue, forKey: "openAIModel") } }
    public var promptTemplate: String { get { defaults.string(forKey: "promptTemplate") ?? PromptTemplate.defaultTemplate } set { defaults.set(newValue, forKey: "promptTemplate") } }

    /// Transcription language for both tracks: "nl_NL" (default) or "en_US".
    public var transcriptionLocaleID: String {
        get { defaults.string(forKey: "transcriptionLocale") ?? "nl_NL" }
        set { defaults.set(newValue, forKey: "transcriptionLocale") }
    }
    public var transcriptionLocale: Locale { Locale(identifier: transcriptionLocaleID) }

    public var recordingsFolder: URL {
        get {
            if let p = defaults.string(forKey: "recordingsFolder") { return URL(fileURLWithPath: p) }
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Hush")
        }
        set { defaults.set(newValue.path, forKey: "recordingsFolder") }
    }

    public var shortcut: Shortcut {
        get {
            guard let d = defaults.data(forKey: "shortcut"), let s = try? JSONDecoder().decode(Shortcut.self, from: d) else { return .default }
            return s
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "shortcut") }
    }

    public var recentParticipants: [String] {
        get { defaults.stringArray(forKey: "recentParticipants") ?? [] }
        set { defaults.set(newValue, forKey: "recentParticipants") }
    }

    /// Remember a name for autocomplete: most recent first, case-insensitive de-dupe, capped.
    public func rememberParticipants(_ names: [String], limit: Int = 50) {
        var list = recentParticipants
        for name in names.reversed() {
            let n = name.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { continue }
            list.removeAll { $0.caseInsensitiveCompare(n) == .orderedSame }
            list.insert(n, at: 0)
        }
        recentParticipants = Array(list.prefix(limit))
    }
}
