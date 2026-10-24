import Foundation

/// What Home and the celebration show about today, derived from the saved data.
struct Today {
    let days: Days
    let key: DayKey
    let streak: StreakState
    let minutes: Double
    let goal: Int
    let nextExam: Exam?
    let lifetimeHours: Double
    let totalXP: Int

    init(_ data: AppData, now: Date = Date()) {
        days = Days(dayStartHour: data.prefs.dayStartHour)
        key = days.key(now)
        streak = Streak.state(data.sessions, today: key, days: days)
        minutes = Rewards.minutes(on: key, data.sessions)
        goal = data.prefs.goalMinutes
        nextExam = data.exams.filter { $0.at > now }.min { $0.at < $1.at }
        lifetimeHours = Rewards.lifetimeHours(data.sessions)
        totalXP = Rewards.totalXP(data.sessions, status: streak.status, days: days)
    }

    /// Monday to Sunday of this week.
    var week: [CompletionSummary.WeekDay] {
        let monday = days.weekStart(key)
        return (0..<7).map { offset in
            let day = days.adding(offset, to: monday)
            return .init(key: day, status: streak.status[day], isToday: day == key)
        }
    }

    /// The next streak milestone ahead.
    var nextMilestone: Int {
        Streak.milestones.first { $0 > streak.current } ?? ((streak.current / 100) + 1) * 100
    }

    var goalProgress: Double { goal > 0 ? min(1, minutes / Double(goal)) : 0 }
    var goalReached: Bool { minutes >= Double(goal) }
    var tier: FlameTier { FlameTier.forStreak(streak.current, lit: streak.todayDone) }

    /// Ember's mood and line on Home, from the hour and whether today's block is done.
    func greeting(hour: Int) -> (mood: Mood, line: String) {
        if streak.todayDone {
            return goalReached
                ? (.cheer, "Goal reached. Ember is blazing.")
                : (.calm, "Streak safe. \(Int(max(0, Double(goal) - minutes))) minutes to today's goal.")
        }
        if let earnBack = streak.earnBack {
            let blocks = earnBack.left == 1 ? "1 more block" : "\(earnBack.left) blocks"
            return (.worried, "Earn back your \(earnBack.restores)-day streak: \(blocks) today.")
        }
        if streak.current == 0 {
            return streak.best > 0
                ? (.calm, "Fresh start. Your best is \(streak.best) days.")
                : (.calm, "Hi, I'm Ember. Let's do your first block.")
        }
        let days = "\(streak.current)-day streak"
        switch hour {
        case 4..<12: return (.calm, "Morning. One block keeps your \(days) alive.")
        case 12..<18: return (.focused, "Still time. One block saves your \(days).")
        case 18..<22: return (.worried, "Evening already. Save your \(days).")
        default: return (.shocked, "It's late! One block before the day ends.")
        }
    }
}
