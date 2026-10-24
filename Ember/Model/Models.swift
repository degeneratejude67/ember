import Foundation

/// A study day as yyyymmdd. The day starts at `Prefs.dayStartHour`, so a block started at
/// 01:30 belongs to the evening before.
typealias DayKey = Int

enum Strictness: String, Codable, CaseIterable, Identifiable {
    /// Timer only: leaving is fine, pausing is fine, no completion bonus.
    case relaxed
    /// Leaving the app for longer than the grace time ends the block unfinished.
    case deep
    /// Deep Focus inside Guided Access.
    case lockIn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .deep: return "Deep Focus"
        case .lockIn: return "Lock In"
        }
    }

    var summary: String {
        switch self {
        case .relaxed: return "Just a timer. Pause any time; no completion bonus."
        case .deep: return "Leave Ember for more than a few seconds and the block ends. Locking the screen is fine."
        case .lockIn: return "Deep Focus inside Guided Access: the iPad stays on Ember until you enter the passcode."
        }
    }

    var polices: Bool { self != .relaxed }
}

enum PresetKind: String, Codable {
    /// Fixed focus and break lengths, with a long break every few rounds.
    case cycle
    /// Count up; the break is a fifth of the focus time.
    case flow
    /// One long block with time checks and no break.
    case exam
    /// "Just 5 minutes": five minutes, then it carries on as Flowtime.
    case starter
}

struct Preset: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var kind: PresetKind
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    /// A long break after every `longEvery` rounds; 0 means never.
    var longEvery: Int
    var note: String

    static let pomodoro = Preset(id: "pomodoro", name: "Pomodoro", kind: .cycle, focusMinutes: 25, shortBreakMinutes: 5,
                                 longBreakMinutes: 15, longEvery: 4, note: "25 on, 5 off, a long break after 4. Fixed breaks mean less fatigue.")
    static let deep = Preset(id: "deep", name: "Deep", kind: .cycle, focusMinutes: 50, shortBreakMinutes: 10,
                             longBreakMinutes: 10, longEvery: 0, note: "50 on, 10 off. A longer stretch for problem sets.")
    static let fiftyTwo = Preset(id: "5217", name: "52/17", kind: .cycle, focusMinutes: 52, shortBreakMinutes: 17,
                                 longBreakMinutes: 17, longEvery: 0, note: "52 on, 17 off. Popular, but the evidence for it is weak.")
    static let ultradian = Preset(id: "ultradian", name: "Ultradian", kind: .cycle, focusMinutes: 90, shortBreakMinutes: 20,
                                  longBreakMinutes: 20, longEvery: 0, note: "90 on, 20 off. Popular, but the evidence for it is weak.")
    static let flow = Preset(id: "flow", name: "Flowtime", kind: .flow, focusMinutes: 0, shortBreakMinutes: 0,
                             longBreakMinutes: 0, longEvery: 0, note: "Count up and stop when your focus drops. The break is a fifth of it.")
    static let exam = Preset(id: "exam", name: "Mock exam", kind: .exam, focusMinutes: 180, shortBreakMinutes: 0,
                             longBreakMinutes: 0, longEvery: 0, note: "A full paper against the clock, with time checks at halfway and 15 minutes left.")
    static let starter = Preset(id: "starter", name: "Just 5 minutes", kind: .starter, focusMinutes: 5, shortBreakMinutes: 0,
                                longBreakMinutes: 0, longEvery: 0, note: "Start small. After 5 minutes it carries on as Flowtime.")
    static let customDefault = Preset(id: "custom", name: "Custom", kind: .cycle, focusMinutes: 30, shortBreakMinutes: 5,
                                      longBreakMinutes: 15, longEvery: 4, note: "Your own rhythm.")

    /// The presets on the technique sheet, in order. Custom and the exam length come from Prefs.
    static let builtIn: [Preset] = [pomodoro, deep, fiftyTwo, ultradian, flow, exam]

    var hasBreaks: Bool { kind != .exam }

    var shortLabel: String {
        switch kind {
        case .cycle: return "\(focusMinutes)/\(shortBreakMinutes)"
        case .flow: return "count up"
        case .exam: return TimeText.minutes(focusMinutes)
        case .starter: return "5 min"
        }
    }
}

enum TimerStyle: String, Codable, CaseIterable, Identifiable {
    case disc, ring, digits

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct StudySubject: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var colorIndex: Int
    var archived = false
}

struct Exam: Codable, Identifiable, Equatable {
    var id = UUID()
    var subjectID: UUID?
    var title: String
    var at: Date
    var targetHours: Double?
    var createdAt = Date()
}

enum Outcome: String, Codable {
    case completed
    /// Ended early: given up, or left the app for too long.
    case unfinished
    /// The app died without a trace (crash, flat battery); counts like a completed block
    /// but earns no bonus.
    case interrupted
}

enum EndReason: String, Codable {
    case finished, gaveUp, left, interrupted
}

/// One finished block in the history.
struct SessionRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    /// The study day the block started in.
    var day: DayKey
    var startedAt: Date
    var endedAt: Date
    var presetID: String
    var presetName: String
    var strictness: Strictness
    var subjectID: UUID?
    var intent: String
    var round: Int
    /// Planned length; nil for count-up blocks.
    var plannedMinutes: Double?
    /// Focus time that counts, in minutes.
    var minutes: Double
    /// Minutes spent inside Guided Access.
    var lockedMinutes: Double
    var slips: Int
    var outcome: Outcome
    var reason: EndReason
    /// What pulled him away, for unfinished blocks.
    var distraction: String?
    /// The goal line's result: done, partly or notYet.
    var intentResult: String?
    var parking: [String] = []
    var examScore: String?
    /// Set when the break after this block ends: true if he stayed off the iPad.
    var cleanBreak: Bool?

    /// Counts toward the streak (at least 10 minutes, not unfinished).
    var qualifies: Bool {
        outcome != .unfinished && minutes >= Rules.qualifyingMinutes
    }
}

enum Rules {
    static let qualifyingMinutes = 10.0
    static let maxFreezes = 2
    static let freezeEvery = 7
    static let earnBackBlocks = 2
    static let earnBackCooldownDays = 14
}

enum TimeText {
    /// "25 min", "1 h 30 min", "3 h".
    static func minutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "4:59" or "1:04:59".
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
