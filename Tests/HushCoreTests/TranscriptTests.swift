import Testing
import Foundation
@testable import HushCore

@Suite struct TranscriptTests {
    @Test func mergeOrdersByStartAndPutsJijFirstOnTies() {
        let mic = [TranscriptSegment(start: 4, end: 8, speaker: .you, text: "Hoi"),
                   TranscriptSegment(start: 20, end: 22, speaker: .you, text: "Tot straks")]
        let sys = [TranscriptSegment(start: 4, end: 9, speaker: .them, text: "Dag"),
                   TranscriptSegment(start: 11, end: 15, speaker: .them, text: "Prima")]
        let merged = Transcript.merge(mic: mic, system: sys)
        #expect(merged.map(\.text) == ["Hoi", "Dag", "Prima", "Tot straks"])
    }

    @Test func mergeDropsBlankSegments() {
        let merged = Transcript.merge(mic: [TranscriptSegment(start: 1, end: 2, speaker: .you, text: "  ")], system: [])
        #expect(merged.isEmpty)
    }

    @Test func renderMatchesSpecFormat() {
        let text = Transcript.render([
            TranscriptSegment(start: 4, end: 9, speaker: .you, text: "Oké, laten we beginnen."),
            TranscriptSegment(start: 11, end: 12, speaker: .them, text: "Prima."),
        ])
        #expect(text == "[00:00:04] Jij: Oké, laten we beginnen.\n[00:00:11] Anderen: Prima.")
    }

    @Test func parseRoundTrips() {
        let original = [TranscriptSegment(start: 3725, end: 3725, speaker: .them, text: "Lange dag: veel werk")]
        #expect(Transcript.parse(Transcript.render(original)) == original)
    }

    @Test func parseFoldsContinuationLines() {
        let parsed = Transcript.parse("[00:00:01] Jij: eerste\nvervolg zonder tijd")
        #expect(parsed.count == 1)
        #expect(parsed[0].text == "eerste vervolg zonder tijd")
    }

    @Test func searchIgnoresCaseAndDiacritics() {
        #expect(Transcript.matches("De Regressiesuite is groen, Oké", query: "oke"))
        #expect(Transcript.matches("anything", query: "  "))
        #expect(!Transcript.matches("hallo", query: "wereld"))
    }
}

@Suite struct PromptTemplateTests {
    @Test func fillsAllVariables() {
        let out = PromptTemplate.fill("{naam} / {deelnemers} / {transcript}", name: "Wim", participants: ["Sanne", "Joris"], transcript: "T")
        #expect(out == "Wim / Sanne, Joris / T")
    }

    @Test func doesNotExpandPlaceholdersInsideTranscript() {
        let out = PromptTemplate.fill("{transcript}", name: "Wim", participants: [], transcript: "zeg {naam}")
        #expect(out == "zeg {naam}")
    }

    @Test func defaultTemplateContainsAllVariables() {
        for v in ["{naam}", "{deelnemers}", "{transcript}"] { #expect(PromptTemplate.defaultTemplate.contains(v)) }
    }
}
