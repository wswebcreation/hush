import Foundation

/// Wall clock for a recording, independent of any audio track: a silent or stalled microphone must not freeze the timer.
public struct RecordingClock: Equatable, Sendable {
    public let start: Date
    private var pausedTotal: TimeInterval = 0
    private var pausedSince: Date?

    public init(start: Date) { self.start = start }

    public mutating func pause(at now: Date = Date()) { if pausedSince == nil { pausedSince = now } }

    public mutating func resume(at now: Date = Date()) {
        if let since = pausedSince { pausedTotal += now.timeIntervalSince(since); pausedSince = nil }
    }

    /// Recorded time: since the start, minus time spent paused.
    public func elapsed(at now: Date = Date()) -> TimeInterval {
        let current = pausedSince.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(start) - pausedTotal - current)
    }
}
