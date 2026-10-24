import Foundation

/// Study-day arithmetic. A study day starts at `dayStartHour` (4 am by default), so 01:30 on
/// the 25th belongs to the 24th. Day maths goes through noon so daylight-saving changes
/// can't skip or repeat a day.
struct Days {
    var dayStartHour: Int
    var calendar: Calendar = .current

    func key(_ date: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        var noon = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12))!
        if (c.hour ?? 12) < dayStartHour {
            noon = calendar.date(byAdding: .day, value: -1, to: noon)!
        }
        return Days.key(fromNoon: noon, calendar)
    }

    /// Noon on that day.
    func noon(_ key: DayKey) -> Date {
        calendar.date(from: DateComponents(year: key / 10000, month: (key / 100) % 100, day: key % 100, hour: 12))!
    }

    func adding(_ days: Int, to key: DayKey) -> DayKey {
        Days.key(fromNoon: calendar.date(byAdding: .day, value: days, to: noon(key))!, calendar)
    }

    func distance(from a: DayKey, to b: DayKey) -> Int {
        calendar.dateComponents([.day], from: noon(a), to: noon(b)).day ?? 0
    }

    /// When the study day starts (e.g. 04:00 on that date).
    func start(_ key: DayKey) -> Date {
        calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: noon(key))!
    }

    /// Monday of the week containing `key`.
    func weekStart(_ key: DayKey) -> DayKey {
        let weekday = calendar.component(.weekday, from: noon(key)) // 1 = Sunday
        let back = (weekday + 5) % 7
        return adding(-back, to: key)
    }

    private static func key(fromNoon date: Date, _ calendar: Calendar) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return c.year! * 10000 + c.month! * 100 + c.day!
    }
}
