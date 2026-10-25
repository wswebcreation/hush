import Foundation

public struct ReleaseEntry: Equatable, Sendable {
    public let version: String
    public let notes: [String]
    public init(version: String, notes: [String]) { self.version = version; self.notes = notes }
}

/// What to show when Hush opens: the intro and release notes after an update, the permission steps when access is missing.
public enum ReleaseNotes {
    /// Newest first. Add an entry here for every release; `Info.plist` must carry the same version.
    public static let entries: [ReleaseEntry] = [
        ReleaseEntry(version: "1.0.3", notes: [
            "Tabellen in de notities worden nu ook in de app als tabel getoond.",
            "Het scherm met wat er nieuw is toont voortaan alle wijzigingen, niet alleen de laatste.",
        ]),
        ReleaseEntry(version: "1.0.2", notes: [
            "Hush kon crashen bij het sluiten van een scherm, bijvoorbeeld na het geven van toegang tot de microfoon. Dat is verholpen.",
        ]),
        ReleaseEntry(version: "1.0.1", notes: [
            "Tabellen in de notities staan nu als echte tabellen in het Word-document.",
        ]),
        ReleaseEntry(version: "1.0", notes: [
            "Neem gesprekken op vanuit de menubalk, met je microfoon en het geluid van je Mac.",
            "Het transcript maakt je Mac zelf; je audio verlaat je Mac nooit.",
            "Laat op verzoek Claude of ChatGPT notities maken, met de namen van de deelnemers erin.",
            "Notities worden bewaard als Word-document, met per opname de tokens en geschatte kosten.",
            "Hush vraagt bij het openen om de toegang die nog ontbreekt (microfoon en systeemaudio).",
            "Na een update zie je de uitleg over Hush en wat er nieuw is.",
        ]),
    ]

    /// Every release up to and including `current`, newest first. The changelog screen shows the whole history.
    public static func entries(upTo current: String, in list: [ReleaseEntry] = ReleaseNotes.entries) -> [ReleaseEntry] {
        list.filter { compare($0.version, current) != .orderedDescending }
    }

    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: .numeric)
    }
}

public enum LaunchPlan: Equatable, Sendable {
    /// Very first launch: the story, then the permission steps, then the help.
    case firstRun
    /// A newer version than the one last opened; `notes` is the full changelog. The Hush story is only repeated for a new major or minor version.
    case updated(notes: [ReleaseEntry], showIntro: Bool)
    case nothing

    public static func decide(onboardingDone: Bool, lastSeenVersion: String?, current: String,
                              releases: [ReleaseEntry] = ReleaseNotes.entries) -> LaunchPlan {
        guard onboardingDone else { return .firstRun }
        if let last = lastSeenVersion, ReleaseNotes.compare(last, current) != .orderedAscending { return .nothing }
        return .updated(notes: ReleaseNotes.entries(upTo: current, in: releases),
                        showIntro: lastSeenVersion.map { majorMinor($0) != majorMinor(current) } ?? true)
    }

    private static func majorMinor(_ version: String) -> [Substring] { Array(version.split(separator: ".").prefix(2)) }
}
