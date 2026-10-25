import Foundation

/// Reveals a list of text segments one character at a time. Pure and clock-injected so it is testable.
public struct Typewriter: Sendable {
    public struct Frame: Sendable, Equatable {
        public var visible: [String]
        public var isTyping: Bool
        public var isFinished: Bool
        /// 1 while characters appear, easing to 0 shortly after a segment ends. Drives the logo animation.
        public var activity: Double
    }

    public let segments: [String]
    public let charInterval: TimeInterval
    public let segmentPause: TimeInterval
    public let settle: TimeInterval

    public init(segments: [String], charInterval: TimeInterval = 0.03, segmentPause: TimeInterval = 0.5, settle: TimeInterval = 0.4) {
        self.segments = segments; self.charInterval = charInterval; self.segmentPause = segmentPause; self.settle = settle
    }

    private func start(of index: Int) -> TimeInterval {
        segments[..<index].reduce(0) { $0 + Double($1.count) * charInterval + segmentPause }
    }

    /// Time at which the last character appears.
    public var duration: TimeInterval {
        guard !segments.isEmpty else { return 0 }
        return start(of: segments.count - 1) + Double(segments[segments.count - 1].count) * charInterval
    }

    public func frame(at time: TimeInterval) -> Frame {
        var visible: [String] = []
        var typing = false
        var activity = 0.0
        for (i, text) in segments.enumerated() {
            let begin = start(of: i)
            let typed = min(text.count, max(0, Int((time - begin) / charInterval)))
            visible.append(String(text.prefix(typed)))
            let end = begin + Double(text.count) * charInterval
            if time >= begin, time < end { typing = true; activity = 1 }
            else if time >= end, settle > 0, !typing { activity = max(activity, 1 - (time - end) / settle) }
        }
        return Frame(visible: visible, isTyping: typing, isFinished: time >= duration, activity: max(0, min(1, activity)))
    }
}
