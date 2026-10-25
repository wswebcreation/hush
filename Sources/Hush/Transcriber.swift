import AVFoundation
import Speech
import HushCore

enum TranscriberError: Error { case unsupportedLocale, assetsMissing, empty }

/// On-device transcription. Uses SpeechTranscriber when it supports the locale and falls back to
/// DictationTranscriber otherwise (SpeechTranscriber has no Dutch model on some macOS versions).
enum Transcriber {
    private static func same(_ a: Locale, _ b: Locale) -> Bool { a.identifier(.bcp47) == b.identifier(.bcp47) }

    private static func prefersSpeechTranscriber(_ locale: Locale) async -> Bool {
        await SpeechTranscriber.supportedLocales.contains { same($0, locale) }
    }

    private static func module(for locale: Locale) async throws -> any SpeechModule {
        if await prefersSpeechTranscriber(locale) {
            return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        }
        guard await DictationTranscriber.supportedLocales.contains(where: { same($0, locale) }) else {
            throw TranscriberError.unsupportedLocale
        }
        return DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [],
                                    reportingOptions: [], attributeOptions: [.audioTimeRange])
    }

    /// True when the locale's model is installed on this Mac.
    static func assetsInstalled(for locale: Locale) async -> Bool {
        if await prefersSpeechTranscriber(locale) {
            return await SpeechTranscriber.installedLocales.contains { same($0, locale) }
        }
        return await DictationTranscriber.installedLocales.contains { same($0, locale) }
    }

    /// Downloads the language model if needed (the system manages it).
    static func installAssets(for locale: Locale) async throws {
        let m = try await module(for: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [m]) {
            try await request.downloadAndInstall()
        }
    }

    /// Transcribes one audio file. `progress` receives 0...1 based on the audio time covered so far.
    static func transcribe(file url: URL, speaker: Speaker, locale: Locale,
                           progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
        let m = try await module(for: locale)
        guard await assetsInstalled(for: locale) else { throw TranscriberError.assetsMissing }

        let analyzer = SpeechAnalyzer(modules: [m])
        let file = try AVAudioFile(forReading: url)
        let total = max(Double(file.length) / file.processingFormat.sampleRate, 0.001)

        let collector = Task { () -> [TranscriptSegment] in
            var segments: [TranscriptSegment] = []
            func add(text: AttributedString, range: CMTimeRange) {
                let s = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty {
                    segments.append(TranscriptSegment(start: range.start.seconds, end: range.end.seconds, speaker: speaker, text: s))
                }
                progress(min(1, range.end.seconds / total))
            }
            if let t = m as? SpeechTranscriber {
                for try await r in t.results where r.isFinal { add(text: r.text, range: r.range) }
            } else if let t = m as? DictationTranscriber {
                for try await r in t.results where r.isFinal { add(text: r.text, range: r.range) }
            }
            return segments
        }

        do {
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await collector.value
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }
}
