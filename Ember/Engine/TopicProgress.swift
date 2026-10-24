import Foundation

/// His answer to "How well do you know it now?" after a block on a topic.
enum TopicRating: String, CaseIterable, Identifiable {
    case shaky, okay, solid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shaky: return "Still shaky"
        case .okay: return "Getting there"
        case .solid: return "Got it"
        }
    }
}

/// Topic progress, spaced reviews and exam readiness, as pure functions.
enum TopicProgress {
    /// Days until the next review, by step on the ladder. Three "Got it" answers in a row
    /// (step 3, a two-week gap) make a topic mastered.
    static let intervals = [1, 3, 7, 14, 30]
    static let masteredStep = 3

    /// Moves a topic after a rating: "Still shaky" goes back to the bottom of the ladder,
    /// "Getting there" holds it (at least the first rung), "Got it" climbs one rung.
    static func rate(_ topic: Topic, _ rating: TopicRating, now: Date, calendar: Calendar = .current) -> Topic {
        var t = topic
        switch rating {
        case .shaky:
            t.reviewStep = 0
            t.status = .learning
        case .okay:
            t.reviewStep = max(1, min(t.reviewStep, masteredStep - 1))
            t.status = .reviewed
        case .solid:
            t.reviewStep = min(intervals.count - 1, t.reviewStep + 1)
            t.status = t.reviewStep >= masteredStep ? .mastered : .reviewed
        }
        t.lastStudied = now
        t.reviewDue = calendar.date(byAdding: .day, value: intervals[t.reviewStep], to: calendar.startOfDay(for: now))
        return t
    }

    /// Changing the status by hand keeps the review ladder roughly in step with it.
    static func set(_ topic: Topic, status: TopicStatus, now: Date, calendar: Calendar = .current) -> Topic {
        var t = topic
        t.status = status
        switch status {
        case .notStarted:
            t.reviewStep = 0
            t.reviewDue = nil
        case .learning:
            t.reviewStep = 0
            t.reviewDue = calendar.date(byAdding: .day, value: intervals[0], to: calendar.startOfDay(for: now))
        case .reviewed:
            t.reviewStep = max(1, min(t.reviewStep, masteredStep - 1))
            t.reviewDue = calendar.date(byAdding: .day, value: intervals[t.reviewStep], to: calendar.startOfDay(for: now))
        case .mastered:
            t.reviewStep = max(masteredStep, t.reviewStep)
            t.reviewDue = calendar.date(byAdding: .day, value: intervals[t.reviewStep], to: calendar.startOfDay(for: now))
        }
        return t
    }

    static func isDue(_ topic: Topic, now: Date) -> Bool {
        guard topic.status != .notStarted, let due = topic.reviewDue else { return false }
        return due <= now
    }

    /// Share of a course done, 0...1: each topic counts by its status, high-yield topics twice.
    static func progress(_ topics: [Topic]) -> Double {
        let total = topics.reduce(0.0) { $0 + ($1.starred ? 2 : 1) }
        guard total > 0 else { return 0 }
        return topics.reduce(0.0) { $0 + $1.status.weight * ($1.starred ? 2 : 1) } / total
    }

    /// What to study next in a course: reviews that are due (high-yield first, then the most
    /// overdue), then topics not yet reviewed, high-yield first, in course order.
    static func next(_ topics: [Topic], now: Date, limit: Int = 3) -> [Topic] {
        let due = topics.filter { isDue($0, now: now) }
            .sorted { ($0.starred ? 0 : 1, $0.reviewDue ?? now) < ($1.starred ? 0 : 1, $1.reviewDue ?? now) }
        let fresh = topics.filter { $0.status == .notStarted || $0.status == .learning }
            .filter { t in !due.contains { $0.id == t.id } }
            .sorted { ($0.starred ? 0 : 1, $0.order) < ($1.starred ? 0 : 1, $1.order) }
        return Array((due + fresh).prefix(limit))
    }

    /// Topics left to get to "reviewed" before an exam, and how many a day that needs.
    static func pace(_ topics: [Topic], examAt: Date, now: Date, calendar: Calendar = .current) -> (left: Int, perDay: Double, days: Int) {
        let left = topics.filter { $0.status == .notStarted || $0.status == .learning }.count
        let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                  to: calendar.startOfDay(for: examAt)).day ?? 0)
        return (left, days > 0 ? Double(left) / Double(days) : Double(left), days)
    }

    /// Focus minutes logged on each topic.
    static func minutes(_ sessions: [SessionRecord]) -> [UUID: Double] {
        var minutes: [UUID: Double] = [:]
        for session in sessions {
            if let id = session.topicID { minutes[id, default: 0] += session.minutes }
        }
        return minutes
    }
}
