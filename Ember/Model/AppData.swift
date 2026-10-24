import Foundation

/// App-wide settings.
struct Prefs: Codable, Equatable {
    var goalMinutes = 60
    var dayStartHour = 4
    var strictness: Strictness = .deep
    /// How long he may be away from Ember (another app) before it checks in: 10 s is strict;
    /// from 2 minutes up, Ember asks "Still studying?" when the time is up and ends the block
    /// only if there is no answer within a minute.
    var graceSeconds = 180
    /// Time allowed in helper apps (Safari, YouTube, Gemini, Claude) before Ember checks in.
    var helperSeconds = 600
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
    /// The topic for the next block, when the subject has topics.
    var topicID: UUID?
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
        helperSeconds = c.value(.helperSeconds, d.helperSeconds)
        timerStyle = c.value(.timerStyle, d.timerStyle)
        soundsOn = c.value(.soundsOn, d.soundsOn)
        noise = c.optional(.noise)
        noiseVolume = c.value(.noiseVolume, d.noiseVolume)
        remindersOn = c.value(.remindersOn, d.remindersOn)
        reminderMinute = c.value(.reminderMinute, d.reminderMinute)
        presetID = c.value(.presetID, d.presetID)
        subjectID = c.optional(.subjectID)
        studyAppID = c.optional(.studyAppID)
        topicID = c.optional(.topicID)
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
    var topics: [Topic] = []
    var papers: [PastPaper] = []
    /// A session left with "Break to menu", to continue from Home.
    var resume: ResumePoint?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = c.value(.schema, 1)
        prefs = c.value(.prefs, Prefs())
        subjects = c.value(.subjects, LossyArray<StudySubject>()).items
        exams = c.value(.exams, LossyArray<Exam>()).items
        sessions = c.value(.sessions, LossyArray<SessionRecord>()).items
        topics = c.value(.topics, LossyArray<Topic>()).items
        papers = c.value(.papers, LossyArray<PastPaper>()).items
        resume = c.optional(.resume)
    }

    /// A course's topics in their order.
    func topics(of subjectID: UUID?) -> [Topic] {
        guard let subjectID else { return [] }
        return topics.filter { $0.subjectID == subjectID }.sorted { $0.order < $1.order }
    }

    func topic(_ id: UUID?) -> Topic? {
        guard let id else { return nil }
        return topics.first { $0.id == id }
    }

    func papers(of subjectID: UUID?) -> [PastPaper] {
        guard let subjectID else { return [] }
        return papers.filter { $0.subjectID == subjectID }.sorted { $0.session > $1.session }
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

/// Where to pick a session up again after "Break to menu".
struct ResumePoint: Codable, Equatable {
    var config: SessionConfig
    var round: Int
    var at: Date
}
