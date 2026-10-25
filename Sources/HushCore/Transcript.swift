import Foundation

public enum Speaker: String, Codable, Sendable {
    case you = "Jij"
    case them = "Anderen"
}

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var speaker: Speaker
    public var text: String

    public init(start: Double, end: Double, speaker: Speaker, text: String) {
        self.start = start; self.end = end; self.speaker = speaker; self.text = text
    }
}

public enum Transcript {
    /// Merge the mic and system passes by start time. Ties put "Jij" first. Blank segments are dropped.
    public static func merge(mic: [TranscriptSegment], system: [TranscriptSegment]) -> [TranscriptSegment] {
        (mic + system)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { a, b in
                if a.start != b.start { return a.start < b.start }
                return a.speaker == .you && b.speaker == .them
            }
    }

    /// `[00:00:04] Jij: text`, one line per segment.
    public static func render(_ segments: [TranscriptSegment]) -> String {
        segments.map { "[\(DutchFormat.clock($0.start))] \($0.speaker.rawValue): \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n")
    }

    /// Inverse of `render`; lines that do not match are folded into the previous line.
    public static func parse(_ text: String) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let seg = parseLine(String(line)) {
                result.append(seg)
            } else if !result.isEmpty {
                result[result.count - 1].text += " " + line.trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }

    private static func parseLine(_ line: String) -> TranscriptSegment? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let stamp = line[line.index(after: line.startIndex)..<close].split(separator: ":")
        guard stamp.count == 3, let h = Double(stamp[0]), let m = Double(stamp[1]), let s = Double(stamp[2]) else { return nil }
        let rest = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        for speaker in [Speaker.you, .them] {
            let prefix = speaker.rawValue + ":"
            if rest.hasPrefix(prefix) {
                let start = h * 3600 + m * 60 + s
                return TranscriptSegment(start: start, end: start, speaker: speaker,
                                         text: rest.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    /// Case-insensitive, diacritic-insensitive match used by library search.
    public static func matches(_ haystack: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        return haystack.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
