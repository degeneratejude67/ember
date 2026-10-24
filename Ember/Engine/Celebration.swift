import Foundation

/// Everything the celebration shows about one completed block: what changed between the
/// history without it and with it.
struct CompletionSummary: Equatable {
    let record: SessionRecord
    let xp: Int
    let streakBefore: Int
    let streakAfter: Int
    /// This block was the first qualifying one of its day, so the streak grew.
    let extendedStreak: Bool
    let milestone: Int?
    let tierBefore: FlameTier
    let tierAfter: FlameTier
    let freezeEarned: Bool
    let earnedBack: Bool
    let minutesBefore: Double
    let minutesAfter: Double
    let goal: Int
    let rankBefore: Rewards.Rank
    let rankAfter: Rewards.Rank
    let hoursAfter: Double
    /// Monday to Sunday of the block's week, with each day's status after this block.
    let week: [WeekDay]
    let firstEver: Bool

    struct WeekDay: Equatable {
        let key: DayKey
        let status: DayStatus?
        let isToday: Bool
    }

    enum Step: Equatable {
        case complete, streak, goal, rankUp
    }

    var goalReachedNow: Bool { minutesBefore < Double(goal) && minutesAfter >= Double(goal) }
    var rankUp: Bool { rankAfter.index > rankBefore.index }

    /// The screens to show, at most four; the block screen always comes first.
    var steps: [Step] {
        var steps: [Step] = [.complete]
        if extendedStreak || earnedBack { steps.append(.streak) }
        if goalReachedNow { steps.append(.goal) }
        if rankUp { steps.append(.rankUp) }
        return steps
    }

    static func make(record: SessionRecord, data: AppData, now: Date = Date()) -> CompletionSummary {
        let days = Days(dayStartHour: data.prefs.dayStartHour)
        let today = max(days.key(now), record.day)
        let after = data.sessions.contains { $0.id == record.id } ? data.sessions : data.sessions + [record]
        let before = after.filter { $0.id != record.id }
        let stateBefore = Streak.state(before, today: today, days: days)
        let stateAfter = Streak.state(after, today: today, days: days)
        let welcome = Rewards.welcomeBackIDs(after, status: stateAfter.status, days: days)
        let firstQualifying = after.filter { $0.day == record.day && $0.qualifies }
            .min { $0.startedAt < $1.startedAt }?.id == record.id
        let extended = record.qualifies && firstQualifying
        let hoursBefore = Rewards.lifetimeHours(before)
        let hoursAfter = Rewards.lifetimeHours(after)
        let monday = days.weekStart(record.day)
        let week = (0..<7).map { offset -> WeekDay in
            let key = days.adding(offset, to: monday)
            return WeekDay(key: key, status: stateAfter.status[key], isToday: key == record.day)
        }
        return CompletionSummary(
            record: record,
            xp: Rewards.xp(record, welcomeBack: welcome.contains(record.id)),
            streakBefore: stateBefore.current,
            streakAfter: stateAfter.current,
            extendedStreak: extended,
            milestone: extended ? Streak.milestone(from: stateBefore.current, to: stateAfter.current) : nil,
            tierBefore: FlameTier.forStreak(stateBefore.current, lit: true),
            tierAfter: FlameTier.forStreak(stateAfter.current, lit: true),
            freezeEarned: stateAfter.freezes > stateBefore.freezes,
            earnedBack: stateAfter.status.values.filter { $0 == .repaired }.count
                > stateBefore.status.values.filter { $0 == .repaired }.count,
            minutesBefore: Rewards.minutes(on: record.day, before),
            minutesAfter: Rewards.minutes(on: record.day, after),
            goal: data.prefs.goalMinutes,
            rankBefore: Rewards.rank(hours: hoursBefore),
            rankAfter: Rewards.rank(hours: hoursAfter),
            hoursAfter: hoursAfter,
            week: week,
            firstEver: !before.contains { $0.qualifies } && record.qualifies)
    }
}
