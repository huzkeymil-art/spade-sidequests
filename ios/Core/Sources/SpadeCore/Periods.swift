import Foundation

// Time in Spade is chopped into days, weeks and months. Each one gets a short
// name called a "key", like "2026-11-14". Two moments belong to the same day
// exactly when they have the same day key.

/// Knows what day it is where the player is. Tests swap in a fixed time zone.
struct GameClock {
    private var calendar: Calendar
    private var isoCalendar: Calendar

    init(timeZone: TimeZone) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        calendar = gregorian
        // The ISO calendar starts weeks on Monday and numbers them the international way.
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = timeZone
        isoCalendar = iso
    }

    /// The phone's own clock and time zone.
    static var device: GameClock { GameClock(timeZone: .current) }

    private func pad(_ n: Int) -> String {
        n < 10 ? "0\(n)" : "\(n)"
    }

    /// "2026-11-14"
    func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(pad(c.month ?? 0))-\(pad(c.day ?? 0))"
    }

    /// "2026-11"
    func monthKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return "\(c.year ?? 0)-\(pad(c.month ?? 0))"
    }

    /// "2026-W46". A week belongs to the year that holds its Thursday.
    func weekKey(_ date: Date) -> String {
        let c = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-W\(pad(c.weekOfYear ?? 0))"
    }

    /// 0 = Monday ... 6 = Sunday
    func weekdayIndex(_ date: Date) -> Int {
        // Foundation counts Sunday as 1.
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    func periodKey(_ cadence: Cadence, _ date: Date) -> String {
        switch cadence {
        case .daily: return dayKey(date)
        case .weekly: return weekKey(date)
        case .monthly: return monthKey(date)
        }
    }

    /// Turns "2026-11-14" back into a date (at midnight).
    func parseDay(_ key: String) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        var c = DateComponents()
        c.year = parts.count > 0 ? parts[0] : 1970
        c.month = parts.count > 1 ? parts[1] : 1
        c.day = parts.count > 2 ? parts[2] : 1
        return calendar.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    /// The day key `n` days after (or before, if negative) the given one.
    func shiftDay(_ key: String, _ n: Int) -> String {
        let date = calendar.date(byAdding: .day, value: n, to: parseDay(key)) ?? parseDay(key)
        return dayKey(date)
    }

    /// The seven day keys of the week containing `date`, Monday first.
    func weekDays(_ date: Date) -> [String] {
        let monday = shiftDay(dayKey(date), -weekdayIndex(date))
        return (0..<7).map { shiftDay(monday, $0) }
    }

    /// How far through the month `date` is: just above 0 on the 1st, 1 on the last day.
    func monthProgress(_ date: Date) -> Double {
        let day = calendar.component(.day, from: date)
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        return Double(day) / Double(daysInMonth)
    }

    /// The moment the current day, week or month ends and a fresh board is dealt.
    func nextReset(_ cadence: Cadence, _ date: Date) -> Date {
        let today = dayKey(date)
        switch cadence {
        case .daily:
            return parseDay(shiftDay(today, 1))
        case .weekly:
            return parseDay(shiftDay(today, 7 - weekdayIndex(date)))
        case .monthly:
            var c = calendar.dateComponents([.year, .month], from: date)
            c.day = 1
            let first = calendar.date(from: c) ?? date
            return calendar.date(byAdding: .month, value: 1, to: first) ?? date
        }
    }

    /// The hour (0-23) and day parts of a date, for scheduling reminders.
    func components(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    func date(from components: DateComponents) -> Date? {
        calendar.date(from: components)
    }
}

/// "5h 12m", "3d 4h" or "42m": a short countdown.
func formatCountdown(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded(.up)))
    let days = minutes / 1440
    let hours = (minutes % 1440) / 60
    let mins = minutes % 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(mins)m" }
    return "\(mins)m"
}
