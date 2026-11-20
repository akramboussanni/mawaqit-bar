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

enum PrayerSource: String, Codable {
    case mawaqit
    case aladhan
}

/// What the menu bar title counts down to.
enum TitleMode: String, Codable, CaseIterable {
    case nextPrayer
    case timeLeft
}

struct CalculatedPrayerCalendar {
    let calendar: PrayerCalendar
    let method: String
}

struct SavedState: Codable {
    var notificationsEnabled = true
    var slug: String?
    var name: String?
    var calendar: PrayerCalendar?
    var fetched: Date?
    var year: Int?
    var source: PrayerSource?
    var calculationQuery: String?
    var calculationMethod: String?
    var titleMode: TitleMode?
    /// nil means on.
    var showIqama: Bool?
}

struct MosqueResult: Identifiable, Equatable {
    let slug: String
    let name: String
    let location: String?
    var id: String { slug }
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
    /// Minutes after the adhan, when the mosque sets the iqama that way ("+N") rather than as a time.
    var iqamaAfter: Int?

    /// What the row shows: "+10" for a relative iqama, otherwise its time.
    var iqamaLabel: String? { iqamaTime.map { time in iqamaAfter.map { "+\($0)" } ?? time } }

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

    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
