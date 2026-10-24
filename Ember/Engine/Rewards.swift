import Foundation

/// XP, ranks and daily progress, all derived from the history.
enum Rewards {
    static let completionBonus = 10
    static let cleanBreakBonus = 5
    static let welcomeBackBonus = 20
    static let lockInMultiplier = 1.5

    struct Rank: Equatable {
        let index: Int
        let name: String
        let hours: Double
    }

    static let ranks: [Rank] = [
        Rank(index: 0, name: "Spark", hours: 0),
        Rank(index: 1, name: "Ember", hours: 5),
        Rank(index: 2, name: "Flame", hours: 15),
        Rank(index: 3, name: "Blaze", hours: 40),
        Rank(index: 4, name: "Wildfire", hours: 80),
        Rank(index: 5, name: "Inferno", hours: 150),
        Rank(index: 6, name: "Supernova", hours: 300),
    ]

    static func rank(hours: Double) -> Rank {
        ranks.last { hours >= $0.hours } ?? ranks[0]
    }

    static func next(after rank: Rank) -> Rank? {
        rank.index + 1 < ranks.count ? ranks[rank.index + 1] : nil
    }

    /// 0...1 progress from `rank` to the next one.
    static func progress(hours: Double) -> Double {
        let current = rank(hours: hours)
        guard let next = next(after: current) else { return 1 }
        return min(1, max(0, (hours - current.hours) / (next.hours - current.hours)))
    }

    /// XP for one block: 1 per minute (×1.5 inside Guided Access), +10 for completing it
    /// outside Relaxed mode, +5 for a clean break after it, +20 if it ended a missed day.
    static func xp(_ record: SessionRecord, welcomeBack: Bool = false) -> Int {
        let locked = min(record.minutes, record.lockedMinutes)
        var xp = Int(((record.minutes - locked) + locked * lockInMultiplier).rounded(.down))
        if record.outcome == .completed && record.strictness != .relaxed { xp += completionBonus }
        if record.cleanBreak == true { xp += cleanBreakBonus }
        if welcomeBack { xp += welcomeBackBonus }
        return xp
    }

    /// Records that earn the welcome-back bonus: the first qualifying block of a day that
    /// follows a missed day (frozen or repaired days don't count as missed).
    static func welcomeBackIDs(_ sessions: [SessionRecord], status: [DayKey: DayStatus], days: Days) -> Set<UUID> {
        var ids = Set<UUID>()
        var seenDays = Set<DayKey>()
        for record in sessions.sorted(by: { $0.startedAt < $1.startedAt }) where record.qualifies {
            guard !seenDays.contains(record.day) else { continue }
            seenDays.insert(record.day)
            if status[days.adding(-1, to: record.day)] == .missed && seenDays.count > 1 {
                ids.insert(record.id)
            }
        }
        return ids
    }

    static func totalXP(_ sessions: [SessionRecord], status: [DayKey: DayStatus], days: Days) -> Int {
        let welcome = welcomeBackIDs(sessions, status: status, days: days)
        return sessions.reduce(0) { $0 + xp($1, welcomeBack: welcome.contains($1.id)) }
    }

    /// Minutes studied on a day; unfinished blocks count too.
    static func minutes(on day: DayKey, _ sessions: [SessionRecord]) -> Double {
        sessions.filter { $0.day == day }.reduce(0) { $0 + $1.minutes }
    }

    static func lifetimeHours(_ sessions: [SessionRecord]) -> Double {
        sessions.reduce(0) { $0 + $1.minutes } / 60
    }
}
