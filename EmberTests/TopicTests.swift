import XCTest
@testable import Ember

final class TopicTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Dhaka")!
        return c
    }()
    private let course = UUID()

    private func day(_ d: Int, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    private func topic(_ order: Int = 0, _ status: TopicStatus = .notStarted, starred: Bool = false) -> Topic {
        var t = Topic(subjectID: course, title: "Topic \(order)", order: order, starred: starred)
        t.status = status
        return t
    }

    // MARK: - Ratings and the review ladder

    func testGotItClimbsTheLadderToMastered() {
        var t = topic()
        t = TopicProgress.rate(t, .solid, now: day(1), calendar: calendar)
        XCTAssertEqual(t.status, .reviewed)
        XCTAssertEqual(t.reviewDue, calendar.startOfDay(for: day(4)))
        t = TopicProgress.rate(t, .solid, now: day(4), calendar: calendar)
        XCTAssertEqual(t.reviewDue, calendar.startOfDay(for: day(11)))
        t = TopicProgress.rate(t, .solid, now: day(11), calendar: calendar)
        XCTAssertEqual(t.status, .mastered)
        XCTAssertEqual(t.reviewDue, calendar.startOfDay(for: day(25)))
        XCTAssertEqual(t.lastStudied, day(11))
    }

    func testStillShakyGoesBackToTomorrow() {
        var t = topic(0, .mastered)
        t.reviewStep = 3
        t = TopicProgress.rate(t, .shaky, now: day(5), calendar: calendar)
        XCTAssertEqual(t.status, .learning)
        XCTAssertEqual(t.reviewStep, 0)
        XCTAssertEqual(t.reviewDue, calendar.startOfDay(for: day(6)))
    }

    func testGettingThereHoldsTheRung() {
        var t = topic()
        t = TopicProgress.rate(t, .okay, now: day(1), calendar: calendar)
        XCTAssertEqual(t.status, .reviewed)
        XCTAssertEqual(t.reviewStep, 1)
        t = TopicProgress.rate(t, .okay, now: day(4), calendar: calendar)
        XCTAssertEqual(t.reviewStep, 1)
        XCTAssertEqual(t.reviewDue, calendar.startOfDay(for: day(7)))
    }

    func testSettingTheStatusByHand() {
        let t = TopicProgress.set(topic(), status: .mastered, now: day(1), calendar: calendar)
        XCTAssertEqual(t.reviewStep, TopicProgress.masteredStep)
        XCTAssertEqual(t.reviewDue, calendar.startOfDay(for: day(15)))
        let back = TopicProgress.set(t, status: .notStarted, now: day(2), calendar: calendar)
        XCTAssertNil(back.reviewDue)
        XCTAssertFalse(TopicProgress.isDue(back, now: day(30)))
    }

    func testDueReviews() {
        let t = TopicProgress.rate(topic(), .shaky, now: day(1), calendar: calendar)
        XCTAssertFalse(TopicProgress.isDue(t, now: day(1, 22)))
        XCTAssertTrue(TopicProgress.isDue(t, now: day(2, 0)))
    }

    // MARK: - Course progress, suggestions, pace

    func testProgressWeighsStatusAndHighYieldTwice() {
        XCTAssertEqual(TopicProgress.progress([]), 0)
        XCTAssertEqual(TopicProgress.progress([topic(0, .mastered), topic(1, .notStarted)]), 0.5, accuracy: 0.001)
        let weighted = TopicProgress.progress([topic(0, .mastered, starred: true), topic(1, .notStarted)])
        XCTAssertEqual(weighted, 2.0 / 3, accuracy: 0.001)
        XCTAssertEqual(TopicProgress.progress([topic(0, .learning), topic(1, .reviewed)]), (0.35 + 0.7) / 2, accuracy: 0.001)
    }

    func testStudyNextPutsDueReviewsFirstThenHighYield() {
        let due = TopicProgress.rate(topic(5), .shaky, now: day(1), calendar: calendar)
        let plain = topic(1)
        let highYield = topic(3, starred: true)
        let done = topic(2, .mastered)
        let next = TopicProgress.next([plain, highYield, done, due], now: day(3), limit: 3)
        XCTAssertEqual(next.map(\.order), [5, 3, 1])
    }

    func testPaceToTheExam() {
        let topics = [topic(0), topic(1, .learning), topic(2, .reviewed), topic(3)]
        let pace = TopicProgress.pace(topics, examAt: day(25, 9), now: day(24, 20), calendar: calendar)
        XCTAssertEqual(pace.left, 3)
        XCTAssertEqual(pace.days, 1)
        XCTAssertEqual(pace.perDay, 3, accuracy: 0.001)
    }

    func testMinutesPerTopic() {
        let id = UUID()
        var a = Fixtures.record(day: 20261024, start: day(24), minutes: 25, subject: course, outcome: .completed, intent: "")
        a.topicID = id
        var b = a
        b.id = UUID()
        b.minutes = 10
        let c = Fixtures.record(day: 20261024, start: day(24), minutes: 50, subject: course, outcome: .completed, intent: "")
        XCTAssertEqual(TopicProgress.minutes([a, b, c])[id] ?? 0, 35, accuracy: 0.001)
    }

    // MARK: - Importing course files

    private func file(_ json: String) throws -> Importer.File {
        try JSONDecoder().decode(Importer.File.self, from: Data(json.utf8))
    }

    func testImportCreatesSubjectsTopicsAndPapers() throws {
        var data = AppData()
        let changed = Importer.merge(try file(#"""
        {"courses": [{"name": "ME 417 · IC Engines", "code": "ME 417",
          "topics": [{"title": "Emissions", "group": "Monjur Sir", "asked": 41},
                     {"title": "Air capacity", "group": "Monjur Sir", "asked": 40},
                     {"title": "Engine basics", "group": "Anup Sir", "asked": 9},
                     {"title": "Cycles", "group": "Anup Sir", "asked": 12}],
          "papers": ["2023-24", "2022-23"]}]}
        """#), into: &data)
        XCTAssertEqual(changed, 1)
        XCTAssertEqual(data.subjects.map(\.name), ["ME 417 · IC Engines"])
        let topics = data.topics(of: data.subjects[0].id)
        XCTAssertEqual(topics.map(\.title), ["Emissions", "Air capacity", "Engine basics", "Cycles"])
        XCTAssertEqual(topics.filter(\.starred).map(\.title), ["Emissions", "Air capacity"], "the top 30% by questions asked")
        XCTAssertEqual(data.papers(of: data.subjects[0].id).map(\.session), ["2023-24", "2022-23"])
    }

    func testImportMergesIntoAnExistingSubjectByCodeAndSkipsDuplicates() throws {
        var data = AppData()
        let existing = StudySubject(name: "ME417 engines", colorIndex: 0)
        data.subjects = [existing]
        data.topics = [Topic(subjectID: existing.id, title: "Emissions", order: 0)]
        Importer.merge(try file(#"""
        {"courses": [{"name": "ME 417 · IC Engines", "code": "ME 417",
          "topics": [{"title": "emissions"}, {"title": "Supercharging"}]}]}
        """#), into: &data)
        XCTAssertEqual(data.subjects.count, 1)
        XCTAssertEqual(data.topics(of: existing.id).map(\.title), ["Emissions", "Supercharging"])
        XCTAssertEqual(data.topics(of: existing.id).last?.order, 1)
    }

    func testImportReadsTheFolderOnceAndMovesTheFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("Import", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"courses": [{"name": "IPE 431", "topics": [{"title": "Lathe"}]}]}"#.utf8)
            .write(to: folder.appendingPathComponent("courses.json"))
        var data = AppData()
        XCTAssertEqual(Importer.run(into: &data, root: root), 1)
        XCTAssertEqual(Importer.run(into: &data, root: root), 0)
        XCTAssertEqual(data.topics.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Done/courses.json").path))
    }

    func testOldDataWithoutTopicsStillLoads() throws {
        let data = try JSONDecoder.ember.decode(AppData.self, from: Data(#"{"prefs": {"goalMinutes": 90}}"#.utf8))
        XCTAssertTrue(data.topics.isEmpty)
        XCTAssertTrue(data.papers.isEmpty)
        XCTAssertNil(data.prefs.topicID)
    }
}
