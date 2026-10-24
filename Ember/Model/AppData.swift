import Foundation

/// App-wide settings.
struct Prefs: Codable, Equatable {
    var goalMinutes = 60
    var dayStartHour = 4
    var strictness: Strictness = .deep
    var graceSeconds = 10
    var timerStyle: TimerStyle = .disc
    var soundsOn = true
    var noise: NoiseColor?
    var noiseVolume = 0.5
    var remindersOn = true
    /// Minutes after midnight for the first streak reminder, until he has a usual start time.
    var reminderMinute = 20 * 60
    var presetID = Preset.pomodoro.id
    var subjectID: UUID?
    /// Where he studies during blocks; nil means in Ember only (paper, past papers).
    var studyAppID: String?
    var custom = Preset.customDefault
    var examMinutes = 180
    var onboarded = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Prefs()
        goalMinutes = c.value(.goalMinutes, d.goalMinutes)
        dayStartHour = c.value(.dayStartHour, d.dayStartHour)
        strictness = c.value(.strictness, d.strictness)
        graceSeconds = c.value(.graceSeconds, d.graceSeconds)
        timerStyle = c.value(.timerStyle, d.timerStyle)
        soundsOn = c.value(.soundsOn, d.soundsOn)
        noise = c.optional(.noise)
        noiseVolume = c.value(.noiseVolume, d.noiseVolume)
        remindersOn = c.value(.remindersOn, d.remindersOn)
        reminderMinute = c.value(.reminderMinute, d.reminderMinute)
        presetID = c.value(.presetID, d.presetID)
        subjectID = c.optional(.subjectID)
        studyAppID = c.optional(.studyAppID)
        custom = c.value(.custom, d.custom)
        examMinutes = c.value(.examMinutes, d.examMinutes)
        onboarded = c.value(.onboarded, d.onboarded)
    }

    /// The preset chosen on Home, with Custom and the exam length filled in from these settings.
    var preset: Preset { preset(id: presetID) }

    func preset(id: String) -> Preset {
        if id == Preset.customDefault.id { return custom }
        if id == Preset.starter.id { return .starter }
        if id == Preset.exam.id {
            var exam = Preset.exam
            exam.focusMinutes = examMinutes
            return exam
        }
        return Preset.builtIn.first { $0.id == id } ?? .pomodoro
    }
}

/// Everything Ember saves in ember.json. Streak, XP, ranks and goal progress are derived from
/// the history and never stored.
///
/// Fields added later must be optional or get a fallback below, so older files still load.
struct AppData: Codable, Equatable {
    var schema = 1
    var prefs = Prefs()
    var subjects: [StudySubject] = []
    var exams: [Exam] = []
    var sessions: [SessionRecord] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = c.value(.schema, 1)
        prefs = c.value(.prefs, Prefs())
        subjects = c.value(.subjects, LossyArray<StudySubject>()).items
        exams = c.value(.exams, LossyArray<Exam>()).items
        sessions = c.value(.sessions, LossyArray<SessionRecord>()).items
    }

    func subject(_ id: UUID?) -> StudySubject? {
        guard let id else { return nil }
        return subjects.first { $0.id == id }
    }

    var activeSubjects: [StudySubject] { subjects.filter { !$0.archived } }
}

extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` when it is missing or unreadable.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    /// An optional value that is nil when missing or unreadable.
    func optional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

/// Decodes an array but skips elements that fail, so one bad record never loses the rest.
struct LossyArray<Element: Decodable>: Decodable {
    var items: [Element] = []

    init() {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let item = try? container.decode(Element.self) {
                items.append(item)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
    }

    /// Consumes one element of any shape.
    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
