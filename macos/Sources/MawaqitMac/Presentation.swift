import Foundation

/// Shared presentation rules, mirroring the GNOME extension's presentation.js.
enum Presentation {
    static func remaining(until date: Date, now: Date) -> String {
        let minutes = max(1, Int(ceil(date.timeIntervalSince(now) / 60)))
        return minutes >= 60
            ? "\(minutes / 60)h\(String(format: "%02d", minutes % 60))min"
            : "\(minutes)min"
    }

    static func prayerDetail(_ prayer: Prayer, view: ScheduleView) -> String {
        if prayer.id == view.next?.id { return "in \(remaining(until: prayer.start, now: view.now))" }
        guard let end = prayer.end else { return "" }
        let time = ScheduleBuilder.time(end, timezone: view.timezone)
        return end <= view.now ? "Ended \(time)" : "Ends \(time)"
    }

    static func panelTitle(_ view: ScheduleView) -> String {
        let milestones = view.milestones, now = view.now
        if milestones.active && now < milestones.midnight {
            return "Midnight in \(remaining(until: milestones.midnight, now: now))"
        }
        if milestones.active && now < milestones.lastThird {
            return "Last third in \(remaining(until: milestones.lastThird, now: now))"
        }
        if milestones.active && now < view.night.end {
            return "Fajr in \(remaining(until: view.night.end, now: now))"
        }
        if milestones.active {
            return "Sunrise in \(remaining(until: milestones.sunrise, now: now))"
        }
        guard let next = view.next else { return "" }
        return "\(next.name) in \(remaining(until: next.start, now: now))"
    }

    /// Overnight, the open prayer replaces today's row of the same name instead of adding a row.
    static func displayPrayers(_ view: ScheduleView) -> [Prayer] {
        view.today.filter { !$0.isSunrise }.map { prayer in
            if let current = view.current, current.name == prayer.name,
               !view.today.contains(where: { $0.id == current.id }) { return current }
            return prayer
        }
    }

    static func nextSummary(_ view: ScheduleView) -> String {
        guard let next = view.next, !view.today.contains(where: { $0.id == next.id }) else { return "" }
        return "Next: \(next.name) at \(next.time) tomorrow"
    }
}
