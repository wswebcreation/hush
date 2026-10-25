import Foundation

/// Dutch date, time and duration formatting. Uses real formatters, never English names.
public struct DutchFormat: Sendable {
    public let calendar: Calendar
    private let locale = Locale(identifier: "nl_NL")

    public init(calendar: Calendar = .current) {
        var c = calendar
        c.locale = Locale(identifier: "nl_NL")
        self.calendar = c
    }

    private func format(_ date: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    private func fixed(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// "14:00"
    public func time(_ date: Date) -> String { fixed(date, "HH:mm") }

    /// "14:00 tot 14:45"
    public func timeRange(_ start: Date, _ end: Date?) -> String {
        guard let end else { return time(start) }
        return "\(time(start)) tot \(time(end))"
    }

    /// "di 21 okt" (lower case, no trailing dots)
    public func shortDate(_ date: Date) -> String {
        fixed(date, "EEE d MMM").replacingOccurrences(of: ".", with: "").lowercased()
    }

    /// "di 21 okt · 14:00 tot 14:45"
    public func title(_ start: Date, _ end: Date?) -> String {
        "\(shortDate(start)) · \(timeRange(start, end))"
    }

    /// "Dinsdag 21 oktober"
    public func longDate(_ date: Date) -> String {
        let s = fixed(date, "EEEE d MMMM")
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// "Dinsdag 21 oktober · 14:00 tot 14:45"
    public func longTitle(_ start: Date, _ end: Date?) -> String {
        "\(longDate(start)) · \(timeRange(start, end))"
    }

    /// Sidebar group label: Vandaag, Gisteren or "vr 17 okt".
    public func groupLabel(for date: Date, now: Date = Date()) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return L10n.libToday }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return L10n.libYesterday
        }
        return shortDate(date)
    }

    /// "45 min", "1 uur", "1 uur 5 min", "< 1 min"
    public func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if seconds < 30 { return "< 1 min" }
        if minutes < 60 { return "\(max(minutes, 1)) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) uur" : "\(h) uur \(m) min"
    }

    /// "1 min", "ongeveer" estimates for the transcription remainder.
    public func remaining(_ seconds: Double) -> String {
        if seconds < 45 { return "\(max(Int(seconds.rounded()), 5)) sec" }
        return "\(max(Int((seconds / 60).rounded()), 1)) min"
    }

    /// Folder name by start time: "2026-10-21 14.00"
    public func folderName(_ start: Date) -> String { fixed(start, "yyyy-MM-dd HH.mm") }

    /// "00:23:41"
    public static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }
}
