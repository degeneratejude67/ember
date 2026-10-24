import Foundation

/// A reminder to schedule. Identifiers start with "r." so the planner can replace its own
/// requests without touching the session's.
struct PlannedNotice: Equatable {
    let id: String
    let date: Date
    let title: String
    let body: String
}

/// At most two reminders a day, and only on days without a block yet: one at the time he
/// usually starts (the first block of his last study day), and a last call at 10 pm. Plus a
/// reminder the evening before the free signature runs out.
enum NotificationPlan {
    static let lastCallMinute = 22 * 60
    static let daysAhead = 7

    static func plan(_ data: AppData, now: Date, expiry: Date?, calendar: Calendar = .current) -> [PlannedNotice] {
        let days = Days(dayStartHour: data.prefs.dayStartHour, calendar: calendar)
        let today = days.key(now)
        var notices: [PlannedNotice] = []

        if data.prefs.remindersOn {
            let state = Streak.state(data.sessions, today: today, days: days)
            let usual = usualStartMinute(data, days: days) ?? data.prefs.reminderMinute
            for offset in 0..<daysAhead {
                let day = days.adding(offset, to: today)
                if offset == 0 && state.todayDone { continue }
                // a usual start after midnight or close to the last call moves to 8 pm
                let dayStart = data.prefs.dayStartHour * 60
                let firstMinute = usual >= dayStart && usual <= lastCallMinute - 60 ? usual : lastCallMinute - 120
                let first = date(day, minute: firstMinute, days: days)
                let last = date(day, minute: lastCallMinute, days: days)
                let (firstText, lastText) = copy(offset == 0 ? state : nil, variant: day % 4)
                if first > now {
                    notices.append(PlannedNotice(id: "r.\(day).first", date: first, title: firstText.0, body: firstText.1))
                }
                if last > now {
                    notices.append(PlannedNotice(id: "r.\(day).last", date: last, title: lastText.0, body: lastText.1))
                }
            }
        }

        if let expiry {
            var evening = calendar.date(bySettingHour: 19, minute: 0, second: 0,
                                        of: calendar.date(byAdding: .day, value: -1, to: expiry)!)!
            if evening <= now { evening = expiry.addingTimeInterval(-2 * 3600) }
            if evening > now {
                notices.append(PlannedNotice(id: "r.resign", date: evening, title: "Re-sign Ember tonight",
                                             body: "The free signature runs out soon. Plug the iPad into the PC and open iloader. Your streak and history are kept."))
            }
        }
        return notices.sorted { $0.date < $1.date }
    }

    /// Minute of the day when the most recent study day's first block started.
    static func usualStartMinute(_ data: AppData, days: Days) -> Int? {
        guard let lastDay = data.sessions.map(\.day).max(),
              let first = data.sessions.filter({ $0.day == lastDay }).min(by: { $0.startedAt < $1.startedAt }) else { return nil }
        let c = days.calendar.dateComponents([.hour, .minute], from: first.startedAt)
        return (c.hour ?? 20) * 60 + (c.minute ?? 0)
    }

    /// The moment `minute` (after midnight) falls on within study day `day`; minutes before the
    /// day start belong to the next calendar date.
    static func date(_ day: DayKey, minute: Int, days: Days) -> Date {
        let start = days.start(day)
        let fromStart = ((minute - days.dayStartHour * 60) % 1440 + 1440) % 1440
        return start.addingTimeInterval(Double(fromStart) * 60)
    }

    /// Today's copy uses the real numbers; later days stay general, since they are refreshed
    /// every time the app opens.
    private static func copy(_ state: StreakState?, variant: Int) -> ((String, String), (String, String)) {
        if let state {
            if let earnBack = state.earnBack {
                let blocks = earnBack.left == 1 ? "1 block" : "\(earnBack.left) blocks"
                return (("Earn back your streak", "\(blocks) today bring back your \(earnBack.restores)-day streak."),
                        ("Last call to earn it back", "\(blocks) before the day ends and your \(earnBack.restores) days come back."))
            }
            if state.current > 0 {
                return (("Ember is waiting", "One block keeps your \(state.current)-day streak alive."),
                        ("Your \(state.current)-day streak ends tonight", "One block before the day ends saves it."))
            }
        }
        let firsts = [("Ember is waiting", "One focused block today is all it takes."),
                      ("25 minutes?", "That's one Pomodoro. Ember will time it."),
                      ("Your flame is getting cold", "A single block brings it back to life."),
                      ("Exams don't wait", "Neither does Ember. One block today.")]
        let lasts = [("Last call!", "One block before the day ends keeps your streak."),
                     ("Ember is fading", "Ten minutes of focus is enough to count today."),
                     ("Still time tonight", "A short block now keeps the streak alive."),
                     ("Don't let it go out", "One block before bed saves your streak.")]
        return (firsts[variant % firsts.count], lasts[variant % lasts.count])
    }
}
