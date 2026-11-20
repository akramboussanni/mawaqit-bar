import Foundation

struct PrayerCalendar: Codable, Equatable {
    let timezone: String
    let calendar: [[String: [String]]]
    /// Like `calendar`, but each day is Fajr, Dhuhr, Asr, Maghrib, Isha as "HH:MM" or "+N" minutes
    /// after the adhan. Missing from old saved state and from calculated times.
    var iqamaCalendar: [[String: [String]]]?
    var iqamaEnabled: Bool?

    init(timezone: String, calendar: [[String: [String]]], iqamaCalendar: [[String: [String]]]? = nil,
         iqamaEnabled: Bool? = nil) {
        self.timezone = timezone
        self.calendar = calendar
        self.iqamaCalendar = iqamaCalendar
        self.iqamaEnabled = iqamaEnabled
    }

    /// Iqama data is optional: if a mosque sends it in an odd shape, the adhan times still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timezone = try container.decode(String.self, forKey: .timezone)
        calendar = try container.decode([[String: [String]]].self, forKey: .calendar)
        iqamaCalendar = (try? container.decodeIfPresent([[String: [String?]]].self, forKey: .iqamaCalendar))?
            .map { $0.mapValues { $0.map { $0 ?? "" } } }
        iqamaEnabled = try? container.decodeIfPresent(Bool.self, forKey: .iqamaEnabled)
    }
}

/// Where Kimono takes a place's times from.
enum PlaceKind: String, Codable {
    case mawaqit, masjidbox, calculated

    var label: String {
        switch self {
        case .mawaqit: "Mawaqit"
        case .masjidbox: "MasjidBox"
        case .calculated: "Calculated"
        }
    }
}

/// A mosque or a position, as Kimono Times names it (`Place` in Kimono's prayer model).
struct KimonoPlace: Codable, Identifiable, Equatable {
    let id: String
    let kind: PlaceKind
    let name: String
    /// Where it is; for calculated times, the method.
    let detail: String?
    let url: String?
}

/// One day of a timetable: `times` is Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha; `iqama`, when the
/// mosque gives it, is Fajr, Dhuhr, Asr, Maghrib, Isha as "HH:MM" or null.
struct KimonoDay: Codable, Equatable {
    let date: String
    let times: [String]
    var iqama: [String?]?
}

struct KimonoTimetable: Codable, Equatable {
    let timezone: String
    let days: [KimonoDay]

    /// The days in the yearly calendar shape ScheduleBuilder reads: `calendar[month - 1]["<day>"]`.
    /// Kimono sends yesterday to a few weeks ahead, so no month appears for two different years.
    func prayerCalendar() throws -> PrayerCalendar {
        guard TimeZone(identifier: timezone) != nil else {
            throw MawaqitError.message("This place's time zone is invalid.")
        }
        var calendar = Array(repeating: [String: [String]](), count: 12)
        var iqamaCalendar = calendar
        for day in days {
            let parts = day.date.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]),
                  day.times.count == 6 else {
                throw MawaqitError.message("Kimono sent a day of prayer times it couldn't read.")
            }
            calendar[parts[1] - 1][String(parts[2])] = day.times
            // A missing iqama becomes "", which ScheduleBuilder skips like any unreadable time.
            if let iqama = day.iqama, iqama.count == 5 {
                iqamaCalendar[parts[1] - 1][String(parts[2])] = iqama.map { $0 ?? "" }
            }
        }
        return PrayerCalendar(timezone: timezone, calendar: calendar, iqamaCalendar: iqamaCalendar)
    }
}

/// What the link answers: the person's place, its timetable, and why there's none if so.
struct KimonoMine: Codable {
    let place: KimonoPlace?
    let timetable: KimonoTimetable?
    let problem: String?
}

/// What the menu bar title counts down to.
enum TitleMode: String, Codable, CaseIterable {
    case nextPrayer
    case timeLeft
}

struct SavedState: Codable {
    var notificationsEnabled = true
    /// The personal Kimono Times link; nil until someone connects.
    var link: String?
    var place: KimonoPlace?
    var calendar: PrayerCalendar?
    var fetched: Date?
    var titleMode: TitleMode?
    /// nil means on.
    var showIqama: Bool?
}

struct Prayer: Identifiable, Equatable {
    let name: String
    let time: String
    let start: Date
    let isSunrise: Bool
    var end: Date?
    var dayOffset = 0
    var iqama: Date?
    var iqamaTime: String?

    var id: String { "\(name):\(start.timeIntervalSince1970)" }
}

struct NightPeriod {
    let start: Date
    let end: Date
    let midnight: Date
    let lastThird: Date
}

enum NightPhase: String {
    case midnight, lastThird, sunrise
}

struct NightMilestones {
    let midnight: Date
    let lastThird: Date
    let fajr: Date
    let sunrise: Date
    let active: Bool
    let phase: NightPhase?
}

struct ScheduleView {
    let today: [Prayer]
    let next: Prayer?
    let current: Prayer?
    let night: NightPeriod
    let nightActive: Bool
    let lastThirdActive: Bool
    let milestones: NightMilestones
    let now: Date
    let dateText: String
    let timezone: String
}

enum MawaqitError: LocalizedError {
    case message(String)
    /// Kimono answered 401: the link was renewed, so this one is dead.
    case linkExpired(String)

    var errorDescription: String? {
        switch self { case .message(let text), .linkExpired(let text): text }
    }
}
