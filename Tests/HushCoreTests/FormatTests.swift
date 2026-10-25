import Testing
import Foundation
@testable import HushCore

@Suite struct DutchFormatTests {
    let f = amsterdamFormat()

    @Test func titleUsesDutchLowercaseWeekdayAndMonth() {
        #expect(f.title(date(2026, 10, 21, 14, 0), date(2026, 10, 21, 14, 45)) == "wo 21 okt · 14:00 tot 14:45")
    }

    @Test func longTitleIsCapitalised() {
        #expect(f.longTitle(date(2026, 10, 21, 14, 0), date(2026, 10, 21, 14, 45)) == "Woensdag 21 oktober · 14:00 tot 14:45")
    }

    @Test func timeRangeWithoutEndShowsStartOnly() {
        #expect(f.timeRange(date(2026, 10, 21, 9, 5), nil) == "09:05")
    }

    @Test func folderNameUsesDotsInTime() {
        #expect(f.folderName(date(2026, 10, 21, 14, 0)) == "2026-10-21 14.00")
    }

    @Test func groupLabels() {
        let now = date(2026, 10, 25, 12)
        #expect(f.groupLabel(for: date(2026, 10, 25, 8), now: now) == "Vandaag")
        #expect(f.groupLabel(for: date(2026, 10, 24, 23), now: now) == "Gisteren")
        #expect(f.groupLabel(for: date(2026, 10, 17, 10), now: now) == "za 17 okt")
    }

    @Test func durations() {
        #expect(f.duration(10) == "< 1 min")
        #expect(f.duration(45 * 60) == "45 min")
        #expect(f.duration(3600) == "1 uur")
        #expect(f.duration(3900) == "1 uur 5 min")
    }

    @Test func clock() {
        #expect(DutchFormat.clock(23 * 60 + 41) == "00:23:41")
        #expect(DutchFormat.clock(3725) == "01:02:05")
        #expect(DutchFormat.clock(-4) == "00:00:00")
    }
}
