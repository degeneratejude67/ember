import Foundation

/// How well he knows a topic. It moves with his "how well do you know it now?" answers after
/// blocks on that topic, or by hand in the course screen.
enum TopicStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted, learning, reviewed, mastered

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notStarted: return "Not started"
        case .learning: return "Learning"
        case .reviewed: return "Reviewed"
        case .mastered: return "Mastered"
        }
    }

    var icon: String {
        switch self {
        case .notStarted: return "circle"
        case .learning: return "circle.lefthalf.filled"
        case .reviewed: return "checkmark.circle"
        case .mastered: return "checkmark.seal.fill"
        }
    }

    /// Share of the topic counted as done in the course and exam-readiness percentages.
    var weight: Double {
        switch self {
        case .notStarted: return 0
        case .learning: return 0.35
        case .reviewed: return 0.7
        case .mastered: return 1
        }
    }
}

/// One topic of a course (a lecture, a chapter, a kind of question).
struct Topic: Codable, Identifiable, Equatable {
    var id = UUID()
    var subjectID: UUID
    var title: String
    /// A heading the topic sits under, such as the teacher or the half of the course.
    var group: String?
    var order: Int
    var status: TopicStatus = .notStarted
    /// High-yield: asked often in past papers, or starred by hand.
    var starred = false
    /// Past-paper questions on this topic, when known.
    var asked: Int?
    var lastStudied: Date?
    var reviewDue: Date?
    /// Position on the spaced-review ladder (see `TopicProgress.intervals`).
    var reviewStep = 0
    var note = ""

    init(subjectID: UUID, title: String, group: String? = nil, order: Int, asked: Int? = nil, starred: Bool = false) {
        self.subjectID = subjectID
        self.title = title
        self.group = group
        self.order = order
        self.asked = asked
        self.starred = starred
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        subjectID = try c.decode(UUID.self, forKey: .subjectID)
        title = try c.decode(String.self, forKey: .title)
        group = c.optional(.group)
        order = c.value(.order, 0)
        status = c.value(.status, .notStarted)
        starred = c.value(.starred, false)
        asked = c.optional(.asked)
        lastStudied = c.optional(.lastStudied)
        reviewDue = c.optional(.reviewDue)
        reviewStep = c.value(.reviewStep, 0)
        note = c.value(.note, "")
    }
}

/// One past paper of a course, ticked off when he has done it under exam conditions.
struct PastPaper: Codable, Identifiable, Equatable {
    var id = UUID()
    var subjectID: UUID
    /// The session it was set in, e.g. "2019-20".
    var session: String
    var done = false
    var score: String?
    var doneAt: Date?

    init(subjectID: UUID, session: String) {
        self.subjectID = subjectID
        self.session = session
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        subjectID = try c.decode(UUID.self, forKey: .subjectID)
        session = try c.decode(String.self, forKey: .session)
        done = c.value(.done, false)
        score = c.optional(.score)
        doneAt = c.optional(.doneAt)
    }
}
