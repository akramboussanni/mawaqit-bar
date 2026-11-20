import Foundation
import Testing
@testable import MawaqitMac

@Suite("Mawaqit schedule")
struct ScheduleTests {
    @Test func scheduleBuildsPrayerAndNightWindows() throws {
        var months = Array(repeating: [String: [String]](), count: 12)
        for month in months.indices {
            for day in 1...31 {
                months[month][String(day)] = ["05:00", "06:30", "13:00", "16:30", "19:00", "20:30"]
            }
        }
        let data = PrayerCalendar(timezone: "America/Toronto", calendar: months)
        let formatter = ISO8601DateFormatter()
        let now = try #require(formatter.date(from: "2026-09-16T18:00:00Z")) // 14:00 local
        let view = try ScheduleBuilder.build(data, now: now)
        #expect(view.current?.name == "Dhuhr")
        #expect(view.next?.name == "Asr")
        #expect(view.today.count == 6)
    }

    @Test func activePrayerUsesItsOpenWindowNotMostRecentOrNext() throws {
        let days = Dictionary(uniqueKeysWithValues: (1...31).map {
            (String($0), ["05:00", "06:30", "13:00", "16:30", "19:00", "20:30"])
        })
        let data = PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: days, count: 12))
        let formatter = ISO8601DateFormatter()
        for (instant, expectedCurrent, expectedNext) in [
            ("2026-09-19T09:00:00Z", "Fajr", "Dhuhr"),
            ("2026-09-19T10:30:00Z", nil, "Dhuhr"),
            ("2026-09-19T15:36:00Z", nil, "Dhuhr"),
            ("2026-09-19T17:00:00Z", "Dhuhr", "Asr"),
            ("2026-09-19T20:30:00Z", "Asr", "Maghrib"),
        ] as [(String, String?, String)] {
            let now = try #require(formatter.date(from: instant))
            let view = try ScheduleBuilder.build(data, now: now)
            #expect(view.current?.name == expectedCurrent)
            #expect(view.next?.name == expectedNext)
        }
    }

    @Test func kimonoTimetableFillsTheCalendarAcrossTheYearEnd() throws {
        let json = #"""
        {"place":{"id":"mawaqit:example","kind":"mawaqit","name":"Example Mosque","detail":"Gatineau","url":null},
         "timetable":{"place":{"id":"mawaqit:example","kind":"mawaqit","name":"Example Mosque","detail":null,"url":null},
           "timezone":"America/Toronto","fetchedAt":1,
           "days":[{"date":"2026-12-31","times":["06:20","07:40","12:10","14:20","16:30","18:00"],"iqama":null,"jumua":[]},
                   {"date":"2027-01-01","times":["06:21","07:41","12:11","14:21","16:31","18:01"],"iqama":["06:40",null,null,null,null],"jumua":[]},
                   {"date":"2027-01-02","times":["06:22","07:42","12:12","14:22","16:32","18:02"],"iqama":null,"jumua":["13:00"]}]},
         "recent":[]}
        """#
        let mine = try JSONDecoder().decode(KimonoMine.self, from: Data(json.utf8))
        #expect(mine.place?.kind == .mawaqit)
        let calendar = try #require(try mine.timetable?.prayerCalendar())
        #expect(calendar.timezone == "America/Toronto")
        #expect(calendar.calendar[11]["31"]?.first == "06:20")
        #expect(calendar.calendar[0]["1"]?.first == "06:21")
        // New Year’s Day at 13:00 in Toronto: yesterday, today and tomorrow all come from the feed.
        let view = try ScheduleBuilder.build(calendar, now: try #require(ISO8601DateFormatter().date(from: "2027-01-01T18:00:00Z")))
        #expect(view.current?.name == "Dhuhr")
        #expect(view.next?.name == "Asr")
        #expect(calendar.iqamaCalendar?[0]["1"] == ["06:40", "", "", "", ""])
        #expect(calendar.iqamaCalendar?[11]["31"] == nil)
        #expect(view.today.map(\.iqamaTime) == ["06:40", nil, nil, nil, nil, nil])
    }

    @Test func kimonoIqamaShowsAndCountsDown() throws {
        let json = #"""
        {"timezone":"America/Toronto","days":[
          {"date":"2027-01-01","times":["06:21","07:41","12:11","14:21","16:31","18:01"],"iqama":["06:40","12:30","14:35",null,"18:30"]},
          {"date":"2027-01-02","times":["06:22","07:42","12:12","14:22","16:32","18:02"],"iqama":null},
          {"date":"2026-12-31","times":["06:20","07:40","12:10","14:20","16:30","18:00"]}]}
        """#
        let calendar = try JSONDecoder().decode(KimonoTimetable.self, from: Data(json.utf8)).prayerCalendar()
        // 12:22 in Toronto: Dhuhr is open and its iqama is at 12:30.
        let view = try ScheduleBuilder.build(calendar, now: try #require(ISO8601DateFormatter().date(from: "2027-01-01T17:22:00Z")))
        let dhuhr = try #require(view.current)
        #expect(dhuhr.iqamaTime == "12:30")
        #expect(Presentation.currentDetail(dhuhr, view: view) == "Iqama in 8min")
        #expect(Presentation.currentDetail(dhuhr, view: view, showIqama: false) == "Ends at 14:21")
        #expect(view.today.map(\.iqamaTime) == ["06:40", nil, "12:30", "14:35", nil, "18:30"])
        #expect(view.today.map(\.iqamaLabel) == ["06:40", nil, "12:30", "14:35", nil, "18:30"])
    }

    @Test func kimonoRelativeIqamaShowsAsMinutesWithTheRealTimeKept() throws {
        let json = #"""
        {"timezone":"America/Toronto","days":[
          {"date":"2027-01-01","times":["06:21","07:41","12:11","14:21","16:31","18:01"],
           "iqama":["06:40","12:21","14:31",null,"18:30"],"iqamaAfter":[null,10,10,5,null]},
          {"date":"2027-01-02","times":["06:22","07:42","12:12","14:22","16:32","18:02"],"iqama":null,"iqamaAfter":null},
          {"date":"2026-12-31","times":["06:20","07:40","12:10","14:20","16:30","18:00"],"iqama":null}]}
        """#
        let calendar = try JSONDecoder().decode(KimonoTimetable.self, from: Data(json.utf8)).prayerCalendar()
        #expect(calendar.iqamaCalendar?[0]["1"] == ["06:40", "+10", "+10", "+5", "18:30"])
        // 12:13 in Toronto: Dhuhr is open; its iqama shows as +10 and counts down to 12:21.
        let view = try ScheduleBuilder.build(calendar, now: try #require(ISO8601DateFormatter().date(from: "2027-01-01T17:13:00Z")))
        #expect(view.today.map(\.iqamaLabel) == ["06:40", nil, "+10", "+10", "+5", "18:30"])
        let dhuhr = try #require(view.current)
        #expect(dhuhr.iqamaTime == "12:21")
        #expect(Presentation.currentDetail(dhuhr, view: view) == "Iqama in 8min")
        let events = try Presentation.upcomingNotifications(calendar, now: view.now, horizon: 3 * 3600, place: "Test", calculated: false)
        #expect(events.first?.body == "Iqama at 14:31 · Ends at 16:31 (America/Toronto) · Test")
    }

    @Test func kimonoTimetableRefusesUnreadableDays() {
        let bad = KimonoTimetable(timezone: "America/Toronto", days: [KimonoDay(date: "2026-13-01", times: ["05:00"])])
        #expect(throws: (any Error).self) { try bad.prayerCalendar() }
        let zone = KimonoTimetable(timezone: "Mars/Olympus", days: [])
        #expect(throws: (any Error).self) { try zone.prayerCalendar() }
    }

    @Test func aPlaceWithoutATimetableStillDecodes() throws {
        let json = #"{"place":null,"timetable":null,"recent":[],"problem":"Pick a place first."}"#
        let mine = try JSONDecoder().decode(KimonoMine.self, from: Data(json.utf8))
        #expect(mine.place == nil && mine.timetable == nil && mine.problem == "Pick a place first.")
    }

    @Test func countdownsUseCompactMinutesAndNoSeparator() throws {
        let now = Date(timeIntervalSince1970: 0)
        #expect(Presentation.remaining(until: now.addingTimeInterval(8100), now: now) == "2h15min")
        #expect(Presentation.remaining(until: now.addingTimeInterval(3900), now: now) == "1h05min")
        #expect(Presentation.remaining(until: now.addingTimeInterval(840), now: now) == "14min")
        let days = Dictionary(uniqueKeysWithValues: (1...31).map {
            (String($0), ["05:00", "06:30", "13:00", "16:30", "19:00", "20:30"])
        })
        let data = PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: days, count: 12))
        let formatter = ISO8601DateFormatter()
        // 16:45 local: Maghrib at 19:00 is 2h15min away.
        let view = try ScheduleBuilder.build(data, now: try #require(formatter.date(from: "2026-09-19T20:45:00Z")))
        #expect(Presentation.panelTitle(view) == "Maghrib in 2h15min")
        let dhuhr = try #require(view.today.first { $0.name == "Dhuhr" })
        #expect(Presentation.prayerDetail(dhuhr, view: view) == "Ended 16:30")
    }

    @Test func timeLeftNamesTheOpenPrayerAndFallsBackToNextEvent() throws {
        let days = Dictionary(uniqueKeysWithValues: (1...31).map {
            (String($0), ["05:00", "06:30", "13:00", "16:30", "19:00", "20:30"])
        })
        let data = PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: days, count: 12))
        let formatter = ISO8601DateFormatter()
        for (instant, timeLeft, nextPrayer) in [
            ("2026-09-19T23:55:00Z", "Maghrib, 35min left", "Isha in 35min"), // 19:55 local
            ("2026-09-20T01:00:00Z", "Isha, 3h00min left", "Midnight in 3h00min"), // 21:00, Isha ends at midnight
            ("2026-09-19T09:30:00Z", "Fajr, 1h00min left", "Sunrise in 1h00min"), // 05:30
            ("2026-09-19T14:30:00Z", "Dhuhr in 2h30min", "Dhuhr in 2h30min"), // 10:30, no prayer open
            ("2026-09-20T04:30:00Z", "Last third in 1h10min", "Last third in 1h10min"), // 00:30, after midnight
        ] {
            let view = try ScheduleBuilder.build(data, now: try #require(formatter.date(from: instant)))
            #expect(Presentation.panelTitle(view, mode: .timeLeft) == timeLeft)
            #expect(Presentation.panelTitle(view) == nextPrayer)
        }
        let old = try JSONDecoder().decode(SavedState.self, from: Data(#"{"notificationsEnabled":true}"#.utf8))
        #expect(old.titleMode == nil)
    }

    @Test func overnightRowsReplaceInsteadOfAppending() throws {
        let days = Dictionary(uniqueKeysWithValues: (1...31).map {
            (String($0), ["04:00", "05:30", "13:00", "17:00", "21:00", "22:30"])
        })
        let data = PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: days, count: 12))
        let formatter = ISO8601DateFormatter()
        // 00:15 local: yesterday's Isha stays open until Islamic midnight at 00:30.
        let view = try ScheduleBuilder.build(data, now: try #require(formatter.date(from: "2026-09-19T04:15:00Z")))
        let rows = Presentation.displayPrayers(view)
        #expect(rows.count == 5)
        #expect(rows.last?.id == view.current?.id)
        #expect(Presentation.nextSummary(view).isEmpty)
    }

    @Test func notificationsAreScheduledAheadForTwoDays() throws {
        let days = Dictionary(uniqueKeysWithValues: (1...31).map {
            (String($0), ["05:00", "06:30", "13:00", "16:30", "19:00", "20:30"])
        })
        let data = PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: days, count: 12))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-19T18:00:00Z")) // 14:00 local
        let events = try Presentation.upcomingNotifications(data, now: now, place: "Test", calculated: false)
        // Covers the rest of today, all of tomorrow, and the following morning, without duplicates.
        #expect(events.allSatisfy { $0.date > now && $0.date <= now.addingTimeInterval(48 * 3600) })
        #expect(events.first?.title == "Asr time")
        #expect(events.filter { $0.title == "Last third of the night" }.count == 2)
        #expect(Set(events.map(\.id)).count == events.count)
        #expect(events.first?.body == "Ends at 19:00 (America/Toronto) · Test")
        #expect(zip(events, events.dropFirst()).allSatisfy { $0.date <= $1.date })
    }

    private static let iqamaDays = Dictionary(uniqueKeysWithValues: (1...31).map {
        (String($0), ["05:00", "06:30", "13:00", "16:30", "19:00", "20:30"])
    })

    private static func iqamaCalendar(_ iqama: [String], enabled: Bool? = true) -> PrayerCalendar {
        let days = Dictionary(uniqueKeysWithValues: (1...31).map { (String($0), iqama) })
        return PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: iqamaDays, count: 12),
            iqamaCalendar: Array(repeating: days, count: 12), iqamaEnabled: enabled)
    }

    @Test func iqamaResolvesFromMinutesAfterOrClockTime() throws {
        #expect(ScheduleBuilder.iqamaDelay("+10", adhan: "13:00") == 10)
        #expect(ScheduleBuilder.iqamaDelay("+0", adhan: "13:00") == 0)
        #expect(ScheduleBuilder.iqamaDelay("13:15", adhan: "13:00") == 15)
        #expect(ScheduleBuilder.iqamaDelay("00:10", adhan: "23:50") == 20) // after midnight
        for bad in ["", "+", "+-5", "+5m", "abc", "25:00", "13:5", "13"] {
            #expect(ScheduleBuilder.iqamaDelay(bad, adhan: "13:00") == nil)
        }
        let data = Self.iqamaCalendar(["+20", "13:15", "+0", "nope", "20:40"])
        let view = try ScheduleBuilder.build(data, now: try #require(ISO8601DateFormatter().date(from: "2026-09-19T17:00:00Z")))
        let iqama = Dictionary(uniqueKeysWithValues: view.today.map { ($0.name, $0.iqamaTime) })
        #expect(iqama["Fajr"] == "05:20")
        #expect(iqama["Sunrise"] == .some(nil))
        #expect(iqama["Dhuhr"] == "13:15")
        #expect(iqama["Asr"] == "16:30")
        #expect(iqama["Maghrib"] == .some(nil))
        #expect(iqama["Isha"] == "20:40")
        // A relative iqama shows as the mosque set it; a fixed one shows its time.
        let labels = Dictionary(uniqueKeysWithValues: view.today.map { ($0.name, $0.iqamaLabel) })
        #expect(labels["Fajr"] == "+20" && labels["Dhuhr"] == "13:15" && labels["Asr"] == "+0")
        #expect(labels["Maghrib"] == .some(nil) && labels["Sunrise"] == .some(nil))
        #expect(view.today[0].iqamaAfter == 20 && view.today[2].iqamaAfter == nil)
        // 13:15 before Dhuhr's 13:20 adhan means tomorrow, past Asr: dropped rather than shown.
        var late = PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: Dictionary(uniqueKeysWithValues:
            (1...31).map { (String($0), ["05:00", "06:30", "13:20", "16:30", "19:00", "20:30"]) }), count: 12),
            iqamaCalendar: data.iqamaCalendar)
        #expect(try ScheduleBuilder.build(late, now: view.now).today[2].iqama == nil)
        late.iqamaEnabled = false
        #expect(try ScheduleBuilder.build(late, now: view.now).today.allSatisfy { $0.iqama == nil })
    }

    @Test func ishaIqamaCanCrossMidnight() throws {
        let days = Dictionary(uniqueKeysWithValues: (1...31).map {
            (String($0), ["03:30", "05:15", "13:30", "17:45", "21:00", "23:00"])
        })
        let iqama = Dictionary(uniqueKeysWithValues: (1...31).map { (String($0), ["+15", "+10", "+10", "+5", "00:05"]) })
        let data = PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: days, count: 12),
            iqamaCalendar: Array(repeating: iqama, count: 12))
        // 23:30 local; Islamic midnight is 00:15.
        let view = try ScheduleBuilder.build(data, now: try #require(ISO8601DateFormatter().date(from: "2026-06-20T03:30:00Z")))
        let isha = try #require(view.current)
        #expect(isha.name == "Isha" && isha.iqamaTime == "00:05")
        #expect(isha.iqama == isha.start.addingTimeInterval(65 * 60))
        #expect(Presentation.currentDetail(isha, view: view) == "Iqama in 35min")
    }

    @Test func currentRowCountsDownToIqamaThenShowsTheEnd() throws {
        let data = Self.iqamaCalendar(["+20", "13:15", "+10", "+5", "+15"])
        let formatter = ISO8601DateFormatter()
        let early = try ScheduleBuilder.build(data, now: try #require(formatter.date(from: "2026-09-19T17:07:00Z"))) // 13:07
        let dhuhr = try #require(early.current)
        #expect(Presentation.currentDetail(dhuhr, view: early) == "Iqama in 8min")
        // "+10" on the row, but the countdown runs to the real time.
        let asr = try ScheduleBuilder.build(data, now: try #require(formatter.date(from: "2026-09-19T20:32:00Z"))) // 16:32
        let open = try #require(asr.current)
        #expect(open.iqamaLabel == "+10" && open.iqamaTime == "16:40")
        #expect(Presentation.currentDetail(open, view: asr) == "Iqama in 8min")
        #expect(Presentation.currentDetail(dhuhr, view: early, showIqama: false) == "Ends at 16:30")
        let after = try ScheduleBuilder.build(data, now: try #require(formatter.date(from: "2026-09-19T17:15:00Z"))) // 13:15
        #expect(Presentation.currentDetail(try #require(after.current), view: after) == "Ends at 16:30")
        let isha = try ScheduleBuilder.build(data, now: try #require(formatter.date(from: "2026-09-20T01:00:00Z"))) // 21:00
        #expect(Presentation.currentDetail(try #require(isha.current), view: isha) == "Ends at 00:00 · Islamic midnight")
    }

    @Test func notificationsNameTheIqamaFirstAndThePlaceLast() throws {
        let data = Self.iqamaCalendar(["+20", "13:15", "+10", "+5", "+15"])
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-19T18:00:00Z")) // 14:00 local
        let events = try Presentation.upcomingNotifications(data, now: now, place: "Test", calculated: false)
        #expect(events.first?.body == "Iqama at 16:40 · Ends at 19:00 (America/Toronto) · Test")
        let off = try Presentation.upcomingNotifications(data, now: now, place: "Test", calculated: false, showIqama: false)
        #expect(off.first?.body == "Ends at 19:00 (America/Toronto) · Test")
    }

    @Test func missingOrOddIqamaDataLeavesAdhanTimesAlone() throws {
        let old = try JSONDecoder().decode(PrayerCalendar.self, from: Data(#"{"timezone":"America/Toronto","calendar":[]}"#.utf8))
        #expect(old.iqamaCalendar == nil && old.iqamaEnabled == nil)
        let odd = try JSONDecoder().decode(PrayerCalendar.self,
            from: Data(#"{"timezone":"America/Toronto","calendar":[],"iqamaCalendar":"soon","iqamaEnabled":"yes"}"#.utf8))
        #expect(odd.iqamaCalendar == nil && odd.iqamaEnabled == nil)
        let nulls = try JSONDecoder().decode(PrayerCalendar.self,
            from: Data(#"{"timezone":"America/Toronto","calendar":[],"iqamaCalendar":[{"1":["+5",null,"+5","+5","+5"]}]}"#.utf8))
        #expect(nulls.iqamaCalendar?[0]["1"]?[1] == "")
        let state = try JSONDecoder().decode(SavedState.self, from: Data(#"{"notificationsEnabled":true}"#.utf8))
        #expect(state.showIqama == nil)
        // A day with no iqama entry, or too few, shows no iqama.
        let short = PrayerCalendar(timezone: "America/Toronto", calendar: Array(repeating: Self.iqamaDays, count: 12),
            iqamaCalendar: Array(repeating: ["1": ["+5"]], count: 12))
        let view = try ScheduleBuilder.build(short, now: try #require(ISO8601DateFormatter().date(from: "2026-09-19T17:07:00Z")))
        #expect(view.today.allSatisfy { $0.iqama == nil })
        #expect(Presentation.currentDetail(try #require(view.current), view: view) == "Ends at 16:30")
    }
}
