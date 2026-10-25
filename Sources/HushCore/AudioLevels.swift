import Foundation

public enum AudioLevels {
    /// RMS of float samples in 0...1.
    public static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// Maps RMS to a 0...1 meter value on a -60 dB … 0 dB scale.
    public static func meterValue(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db + 60) / 60))
    }
}

/// Tracks how long a source has been silent. Pure and clock-injected so it is testable.
public struct SilenceDetector: Sendable {
    public var threshold: Float
    public var warnAfter: TimeInterval
    private var silentSince: TimeInterval?

    public init(threshold: Float = 0.001, warnAfter: TimeInterval = 60) {
        self.threshold = threshold; self.warnAfter = warnAfter
    }

    /// Feed the current RMS and a monotonically increasing time (seconds of recording).
    public mutating func update(rms: Float, at time: TimeInterval) {
        if rms > threshold { silentSince = nil } else if silentSince == nil { silentSince = time }
    }

    public mutating func reset() { silentSince = nil }

    public func silentDuration(at time: TimeInterval) -> TimeInterval {
        guard let s = silentSince else { return 0 }
        return max(0, time - s)
    }

    public func isWarning(at time: TimeInterval) -> Bool { silentDuration(at: time) > warnAfter }

    /// Whole minutes for the warning copy ("Al 1 min geen geluid"), minimum 1 while warning.
    public func warningMinutes(at time: TimeInterval) -> Int { max(1, Int(silentDuration(at: time) / 60)) }
}

/// Judges a short audio test from meter values (0...1). Pure and clock-injected so it is testable.
public struct LevelTest: Sendable {
    public enum Verdict: Sendable, Equatable { case listening, ok, silent }

    public var threshold: Float
    public var silentAfter: TimeInterval
    public private(set) var peak: Float = 0

    public init(threshold: Float = 0.1, silentAfter: TimeInterval = 3) {
        self.threshold = threshold; self.silentAfter = silentAfter
    }

    public mutating func update(level: Float) { peak = max(peak, level) }

    /// `ok` sticks once any sound was heard; `silent` only after `silentAfter` seconds without any.
    public func verdict(at elapsed: TimeInterval) -> Verdict {
        if peak > threshold { return .ok }
        return elapsed >= silentAfter ? .silent : .listening
    }
}
