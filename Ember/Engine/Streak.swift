import Foundation

enum DayStatus: String, Equatable {
    /// At least one qualifying block.
    case credited
    /// Missed, covered by a streak freeze.
    case frozen
    /// Missed, then earned back with two blocks the next day.
    case repaired
    case missed
    /// Today, before its first qualifying block. Today is never held against the streak.
    case pending
}

struct StreakState: Equatable {
    var current = 0
    var best = 0
    var freezes = 0
    var todayDone = false
    var status: [DayKey: DayStatus] = [:]
    /// Yesterday was missed with no freeze left; finishing the blocks today brings the streak back.
    var earnBack: EarnBack?

    struct EarnBack: Equatable {
        /// The streak that comes back.
        var restores: Int
        var blocksToday: Int
        var needed: Int { Rules.earnBackBlocks }
        var left: Int { max(0, needed - blocksToday) }
    }

    /// The streak ended earlier and no new one has started yet.
    var freshStart: Bool { current == 0 && best > 0 }
}

enum Streak {
    static let milestones = [3, 7, 14, 30, 50, 100, 150, 200, 365]

    /// Qualifying blocks per study day.
    static func qualifying(_ sessions: [SessionRecord]) -> [DayKey: Int] {
        var counts: [DayKey: Int] = [:]
        for session in sessions where session.qualifies {
            counts[session.day, default: 0] += 1
        }
        return counts
    }

    static func state(_ sessions: [SessionRecord], today: DayKey, days: Days) -> StreakState {
        replay(qualifying(sessions), today: today, days: days)
    }

    /// Walks every day from the first qualifying one to today.
    /// - A credited day adds one; every 7th earns a freeze (at most 2 held).
    /// - A missed day uses a freeze if there is one, else it can be earned back with two blocks
    ///   the next day (at most once per 14 days), else the streak resets.
    /// - Frozen and repaired days keep the streak alive without adding to it.
    static func replay(_ qualifying: [DayKey: Int], today: DayKey, days: Days) -> StreakState {
        var state = StreakState()
        state.todayDone = (qualifying[today] ?? 0) > 0
        guard let first = qualifying.filter({ $0.value > 0 }).keys.min(), first <= today else {
            state.status[today] = .pending
            return state
        }
        var streak = 0
        var freezes = 0
        var lastRepair: DayKey?
        var day = first
        while day <= today {
            let blocks = qualifying[day] ?? 0
            if blocks > 0 {
                streak += 1
                if streak % Rules.freezeEvery == 0 { freezes = min(Rules.maxFreezes, freezes + 1) }
                state.status[day] = .credited
            } else if day == today {
                state.status[day] = .pending
            } else if streak == 0 {
                state.status[day] = .missed
            } else if freezes > 0 {
                freezes -= 1
                state.status[day] = .frozen
            } else {
                let next = days.adding(1, to: day)
                let cooledDown = lastRepair.map { days.distance(from: $0, to: day) >= Rules.earnBackCooldownDays } ?? true
                if cooledDown && (qualifying[next] ?? 0) >= Rules.earnBackBlocks {
                    state.status[day] = .repaired
                    lastRepair = day
                } else {
                    if cooledDown && next == today {
                        state.earnBack = .init(restores: streak, blocksToday: qualifying[today] ?? 0)
                    }
                    streak = 0
                    state.status[day] = .missed
                }
            }
            state.best = max(state.best, streak)
            day = days.adding(1, to: day)
        }
        state.current = streak
        state.freezes = freezes
        return state
    }

    /// The milestone crossed when the streak went from `before` to `after`, if any.
    static func milestone(from before: Int, to after: Int) -> Int? {
        var crossed = milestones.filter { before < $0 && $0 <= after }.max()
        let hundred = (after / 100) * 100
        if hundred > 365 && before < hundred && hundred <= after { crossed = hundred }
        return crossed
    }
}
