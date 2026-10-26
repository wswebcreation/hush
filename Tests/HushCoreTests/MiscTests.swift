import Testing
import Foundation
@testable import HushCore

@Suite struct AudioLevelTests {
    @Test func rmsOfConstantSignal() {
        let samples: [Float] = [0.5, -0.5, 0.5, -0.5]
        #expect(samples.withUnsafeBufferPointer { AudioLevels.rms($0) } == 0.5)
    }

    @Test func meterScaleClamps() {
        #expect(AudioLevels.meterValue(rms: 0) == 0)
        #expect(AudioLevels.meterValue(rms: 1) == 1)
        #expect(AudioLevels.meterValue(rms: 2) == 1)
        #expect(abs(AudioLevels.meterValue(rms: 0.0316) - 0.5) < 0.01)  // -30 dB
    }

    @Test func silenceWarnsOnlyAfterSixtySeconds() {
        var d = SilenceDetector()
        d.update(rms: 0.2, at: 0)
        d.update(rms: 0, at: 10)
        #expect(!d.isWarning(at: 70))
        #expect(d.isWarning(at: 71))
        #expect(d.warningMinutes(at: 71) == 1)
        #expect(d.warningMinutes(at: 10 + 185) == 3)
    }

    @Test func soundResetsSilence() {
        var d = SilenceDetector()
        d.update(rms: 0, at: 0)
        d.update(rms: 0.1, at: 90)
        #expect(!d.isWarning(at: 100))
        #expect(d.silentDuration(at: 100) == 0)
    }
}

@Suite struct ShortcutTests {
    @Test func defaultIsOptionCommandR() {
        #expect(Shortcut.default.display == "⌥⌘R")
        #expect(Shortcut.default.keyCaps == ["⌥", "⌘", "R"])
    }

    @Test func requiresAModifier() {
        #expect(Shortcut.default.isValid)
        #expect(!Shortcut(keyCode: 15, modifiers: Shortcut.shiftKey, keyLabel: "r").isValid)
    }
}

@Suite struct SettingsTests {
    func store() -> SettingsStore {
        let name = "hush-test-\(UUID().uuidString)"
        return SettingsStore(defaults: UserDefaults(suiteName: name)!)
    }

    @Test func defaultsMatchSpec() {
        let s = store()
        #expect(s.launchAtLogin)
        #expect(!s.showInDock)
        #expect(s.captureSystemAudio)
        #expect(s.deleteAudioByDefault)
        #expect(s.shortcut == .default)
        #expect(s.lastProvider == .claude)
        #expect(s.promptTemplate == PromptTemplate.defaultTemplate)
        #expect(s.recordingsFolder.path.hasSuffix("Documents/Hush"))
    }

    @Test func participantsAreRememberedMostRecentFirstWithoutDuplicates() {
        let s = store()
        s.rememberParticipants(["Sanne", "Joris"])
        s.rememberParticipants(["sanne", "Mila"])
        #expect(s.recentParticipants == ["sanne", "Mila", "Joris"])
    }

    @Test func shortcutPersists() {
        let s = store()
        let custom = Shortcut(keyCode: 1, modifiers: Shortcut.controlKey | Shortcut.cmdKey, keyLabel: "s")
        s.shortcut = custom
        #expect(s.shortcut == custom)
    }
}

@Suite struct KeyFormatTests {
    @Test func claudeKeysNeedAnthropicPrefix() {
        #expect(KeyFormat.looksValid("sk-ant-api03-abcdefghijklmnopqrstuvwxyz", for: .claude))
        #expect(!KeyFormat.looksValid("sk-proj-abcdefghijklmnopqrstuvwxyz", for: .claude))
    }

    @Test func openAIKeysAcceptProjectKeysButNotAnthropic() {
        #expect(KeyFormat.looksValid("sk-proj-abcdefghijklmnopqrstuvwxyz", for: .openai))
        #expect(!KeyFormat.looksValid("sk-ant-api03-abcdefghijklmnopqrstuvwxyz", for: .openai))
    }

    @Test func rejectsShortTextWhitespaceAndRandomClipboard() {
        #expect(!KeyFormat.looksValid("sk-ant-x", for: .claude))
        #expect(!KeyFormat.looksValid("Dit is een zin met spaties erin zodat hij lang is", for: .openai))
        #expect(!KeyFormat.looksValid("", for: .claude))
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        #expect(KeyFormat.clean("  sk-abc\n") == "sk-abc")
        #expect(KeyFormat.looksValid("\n sk-ant-api03-abcdefghijklmnopqrstuvwxyz \n", for: .claude))
    }

    @Test func keyPagesPointAtProviderConsoles() {
        #expect(NotesProviderKind.claude.keyPageHost == "console.anthropic.com")
        #expect(NotesProviderKind.openai.keyPageHost == "platform.openai.com")
    }
}

@Suite struct LevelTestTests {
    @Test func listensThenGoesSilent() {
        var t = LevelTest()
        t.update(level: 0.02)
        #expect(t.verdict(at: 1) == .listening)
        #expect(t.verdict(at: 3) == .silent)
    }

    @Test func soundIsOkAndSticks() {
        var t = LevelTest()
        t.update(level: 0.6)
        t.update(level: 0)
        #expect(t.verdict(at: 0.1) == .ok)
        #expect(t.verdict(at: 10) == .ok)
    }
}

@Suite struct TypewriterTests {
    private let writer = Typewriter(segments: ["abc", "de"], charInterval: 1, segmentPause: 2, settle: 1)

    @Test func revealsOneCharacterPerInterval() {
        #expect(writer.frame(at: 0).visible == ["", ""])
        #expect(writer.frame(at: 2.5).visible == ["ab", ""])
        #expect(writer.frame(at: 2.5).isTyping)
    }

    @Test func pausesBetweenSegmentsAndSettlesTheLogo() {
        let f = writer.frame(at: 3.5)  // "abc" ended at 3, "de" starts at 5
        #expect(f.visible == ["abc", ""])
        #expect(!f.isTyping)
        #expect(abs(f.activity - 0.5) < 0.001)
        #expect(writer.frame(at: 4.5).activity == 0)
    }

    @Test func finishesWithAllTextShown() {
        #expect(writer.duration == 7)
        let f = writer.frame(at: 100)
        #expect(f.visible == ["abc", "de"])
        #expect(f.isFinished)
        #expect(f.activity == 0)
    }
}

@Suite struct LaunchPlanTests {
    let releases = [ReleaseEntry(version: "1.1", notes: ["b"]), ReleaseEntry(version: "1.0", notes: ["a"])]

    @Test func freshInstallRunsOnboarding() {
        #expect(LaunchPlan.decide(onboardingDone: false, lastSeenVersion: nil, current: "1.1", releases: releases) == .firstRun)
    }

    @Test func sameVersionShowsNothing() {
        #expect(LaunchPlan.decide(onboardingDone: true, lastSeenVersion: "1.1", current: "1.1", releases: releases) == .nothing)
    }

    @Test func updateShowsTheWholeChangelog() {
        let plan = LaunchPlan.decide(onboardingDone: true, lastSeenVersion: "1.0", current: "1.1", releases: releases)
        guard case .updated(let notes) = plan else { Issue.record("expected update"); return }
        #expect(notes.map(\.version) == ["1.1", "1.0"])
    }

    @Test func changelogNeverListsVersionsNewerThanCurrent() {
        let plan = LaunchPlan.decide(onboardingDone: true, lastSeenVersion: nil, current: "1.0", releases: releases)
        guard case .updated(let notes) = plan else { Issue.record("expected update"); return }
        #expect(notes.map(\.version) == ["1.0"])
    }

    @Test func everyUpdateShowsTheFullChangelog() {
        let r = [ReleaseEntry(version: "1.1", notes: ["c"]), ReleaseEntry(version: "1.0.1", notes: ["b"]), ReleaseEntry(version: "1.0", notes: ["a"])]
        #expect(LaunchPlan.decide(onboardingDone: true, lastSeenVersion: "1.0", current: "1.0.1", releases: r) == .updated(notes: [r[1], r[2]]))
        #expect(LaunchPlan.decide(onboardingDone: true, lastSeenVersion: nil, current: "1.1", releases: r) == .updated(notes: r))
    }

    @Test func versionsCompareNumerically() {
        #expect(ReleaseNotes.compare("1.10", "1.9") == .orderedDescending)
    }
}

@Suite struct MarkdownTableTests {
    @Test func parsesRowsAndDropsTheDivider() {
        let rows = MarkdownTable.parse(["| Actie | Eigenaar |", "|---|---|", "| Offerte sturen | **Wim** |"])
        #expect(rows == [["Actie", "Eigenaar"], ["Offerte sturen", "**Wim**"]])
    }

    @Test func recognisesTableLines() {
        #expect(MarkdownTable.isRow("  | a | b |"))
        #expect(!MarkdownTable.isRow("Gewone tekst | met pijp"))
    }
}

@Suite struct RecordingClockTests {
    @Test func countsWallTimeWithoutAnyAudio() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(RecordingClock(start: start).elapsed(at: start.addingTimeInterval(3_261)) == 3_261)
    }

    @Test func pausedTimeIsNotCounted() {
        let start = Date(timeIntervalSince1970: 1_000)
        var clock = RecordingClock(start: start)
        clock.pause(at: start.addingTimeInterval(60))
        #expect(clock.elapsed(at: start.addingTimeInterval(90)) == 60)
        clock.resume(at: start.addingTimeInterval(120))
        #expect(clock.elapsed(at: start.addingTimeInterval(150)) == 90)
    }
}
