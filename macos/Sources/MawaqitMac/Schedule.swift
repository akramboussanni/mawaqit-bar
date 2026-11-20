import Foundation

enum CalendarParser {
    static func parse(html: String) throws -> PrayerCalendar {
        let pattern = #"(?:var|let|const)\s+confData\s*=\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let start = Range(match.range, in: html)?.upperBound else {
            throw MawaqitError.message("Mawaqit did not return a prayer calendar. Try again later.")
        }

        var depth = 0
        var quoted = false
        var escaped = false
        var objectStart: String.Index?
        var index = start
        while index < html.endIndex {
            let character = html[index]
            if quoted {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
            } else if character == "\"" {
                quoted = true
            } else if character == "{" {
                if objectStart == nil { objectStart = index }
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0, let objectStart {
                    let json = String(html[objectStart...index])
                    let data = Data(json.utf8)
                    guard let decoded = try? JSONDecoder().decode(PrayerCalendar.self, from: data),
                          TimeZone(identifier: decoded.timezone) != nil,
                          decoded.calendar.count == 12 else {
                        throw MawaqitError.message("This mosque has an unsupported prayer calendar.")
                    }
                    return decoded
                }
            }
            index = html.index(after: index)
        }
        throw MawaqitError.message("The prayer calendar is incomplete.")
    }

    static func slug(from value: String) throws -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^https://mawaqit\.net/(?:[a-z]{2}/)?(?:m/)?([a-zA-Z0-9_-]+)/?$"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(text.startIndex..., in: text)
        let slug: String
        if let match = regex.firstMatch(in: text, range: range),
           let capture = Range(match.range(at: 1), in: text) {
            slug = String(text[capture])
        } else {
            slug = text
        }
        guard slug.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw MawaqitError.message("Enter a mosque slug or its Mawaqit URL.")
        }
        return slug
    }
}

enum ScheduleBuilder {
    static let names = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]

    static func build(_ data: PrayerCalendar, now: Date = Date()) throws -> ScheduleView {
        guard let zone = TimeZone(identifier: data.timezone) else {
            throw MawaqitError.message("The mosque timezone is invalid.")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let todayStart = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            throw MawaqitError.message("Could not calculate the local date.")
        }
        let dates = [yesterday, todayStart, tomorrow]
        var schedules = try dates.map { date in try prayers(for: date, data: data, calendar: calendar) }
        let nights = try (0..<2).map { index -> NightPeriod in
            let start = schedules[index][4].start
            let end = schedules[index + 1][0].start
            let duration = end.timeIntervalSince(start)
            guard duration > 0 else { throw MawaqitError.message("Invalid sunset-to-Fajr night interval.") }
            return NightPeriod(
                start: start,
                end: end,
                midnight: start.addingTimeInterval(duration / 2),
                lastThird: start.addingTimeInterval(duration * 2 / 3)
            )
        }
        for day in 0..<2 {
            for index in schedules[day].indices where !schedules[day][index].isSunrise {
                let end = index == 5 ? nights[day].midnight : schedules[day][index + 1].start
                schedules[day][index].end = end
                schedules[day][index].dayOffset = day - 1
                // An iqama outside its own prayer's window is bad data, not a late congregation.
                if let iqama = schedules[day][index].iqama, iqama >= end {
                    schedules[day][index].iqama = nil
                    schedules[day][index].iqamaTime = nil
                    schedules[day][index].iqamaAfter = nil
                }
            }
        }
        let today = schedules[1]
        let next = (today + schedules[2]).first { !$0.isSunrise && $0.start > now }
        let current = (schedules[0] + schedules[1]).first {
            !$0.isSunrise && $0.start <= now && now < ($0.end ?? $0.start)
        }
        let night = now < schedules[1][0].start ? nights[0] : nights[1]
        let cycleIndex = now < schedules[1][1].start ? 0 : 1
        let cycleNight = nights[cycleIndex]
        let sunrise = schedules[cycleIndex + 1][1].start
        let cycleActive = now >= schedules[cycleIndex][5].start && now < sunrise
        let phase: NightPhase? = if !cycleActive { nil }
            else if now < cycleNight.midnight { .midnight }
            else if now < cycleNight.lastThird { .lastThird }
            else { .sunrise }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "EEEE, d MMMM"
        return ScheduleView(
            today: today,
            next: next,
            current: current,
            night: night,
            nightActive: night.start <= now && now < night.end,
            lastThirdActive: night.lastThird <= now && now < night.end,
            milestones: NightMilestones(midnight: cycleNight.midnight, lastThird: cycleNight.lastThird, fajr: cycleNight.end,
                sunrise: sunrise, active: cycleActive, phase: phase),
            now: now,
            dateText: formatter.string(from: now),
            timezone: data.timezone
        )
    }

    static func time(_ date: Date, timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Minutes from the adhan to the iqama, from "+N" or a clock time "HH:MM" (taken as the next
    /// day when it is earlier than the adhan, as an Isha iqama after midnight is); nil if unreadable.
    static func iqamaDelay(_ value: String, adhan: String) -> Int? {
        let text = value.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("+") {
            let digits = text.dropFirst()
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let minutes = Int(digits), minutes < 1440 else { return nil }
            return minutes
        }
        func minutes(_ clock: String) -> Int? {
            let pieces = clock.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 2, pieces[1].count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]),
                  (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return hour * 60 + minute
        }
        guard let iqama = minutes(text), let start = minutes(adhan) else { return nil }
        return (iqama - start + 1440) % 1440
    }

    private static func prayers(for date: Date, data: PrayerCalendar, calendar: Calendar) throws -> [Prayer] {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let month = components.month, let day = components.day,
              data.calendar.indices.contains(month - 1),
              let times = data.calendar[month - 1][String(day)], times.count >= 6 else {
            throw MawaqitError.message("No prayer times available for this date.")
        }
        var iqamas: [String]?
        if data.iqamaEnabled != false, let months = data.iqamaCalendar, months.indices.contains(month - 1),
           let values = months[month - 1][String(day)], values.count >= 5 {
            iqamas = values
        }
        return try names.enumerated().map { index, name in
            let pieces = times[index].split(separator: ":")
            guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]),
                  (0...23).contains(hour), (0...59).contains(minute) else {
                throw MawaqitError.message("Invalid prayer time.")
            }
            var instant = components
            instant.hour = hour
            instant.minute = minute
            instant.second = 0
            guard let start = calendar.date(from: instant) else {
                throw MawaqitError.message("Invalid prayer time.")
            }
            var prayer = Prayer(name: name, time: times[index], start: start, isSunrise: index == 1)
            // The iqama list skips sunrise: Fajr, Dhuhr, Asr, Maghrib, Isha.
            if index != 1, let iqamas {
                let value = iqamas[index == 0 ? 0 : index - 1]
                if let delay = iqamaDelay(value, adhan: times[index]) {
                    let iqama = start.addingTimeInterval(TimeInterval(delay * 60))
                    prayer.iqama = iqama
                    prayer.iqamaTime = time(iqama, timezone: data.timezone)
                    if value.trimmingCharacters(in: .whitespaces).hasPrefix("+") { prayer.iqamaAfter = delay }
                }
            }
            return prayer
        }
    }
}
