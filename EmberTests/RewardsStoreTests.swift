import XCTest
@testable import Ember

final class RewardsTests: XCTestCase {
    private func record(_ minutes: Double = 25, outcome: Outcome = .completed, strictness: Strictness = .deep,
                        locked: Double = 0, clean: Bool? = nil) -> SessionRecord {
        var r = Fixtures.record(day: 20261024, start: Date(), minutes: minutes, subject: nil, outcome: outcome, intent: "")
        r.strictness = strictness
        r.lockedMinutes = locked
        r.cleanBreak = clean
        return r
    }

    func testXP() {
        XCTAssertEqual(Rewards.xp(record()), 35)
        XCTAssertEqual(Rewards.xp(record(strictness: .relaxed)), 25, "Relaxed earns no completion bonus")
        XCTAssertEqual(Rewards.xp(record(outcome: .unfinished)), 25, "unfinished minutes still earn their XP")
        XCTAssertEqual(Rewards.xp(record(locked: 25)), 47, "25 locked minutes x 1.5 = 37, +10")
        XCTAssertEqual(Rewards.xp(record(clean: true)), 40)
        XCTAssertEqual(Rewards.xp(record(), welcomeBack: true), 55)
    }

    func testRanks() {
        XCTAssertEqual(Rewards.rank(hours: 0).name, "Spark")
        XCTAssertEqual(Rewards.rank(hours: 4.99).name, "Spark")
        XCTAssertEqual(Rewards.rank(hours: 5).name, "Ember")
        XCTAssertEqual(Rewards.rank(hours: 299.9).name, "Inferno")
        XCTAssertEqual(Rewards.rank(hours: 300).name, "Supernova")
        XCTAssertNil(Rewards.next(after: Rewards.rank(hours: 1000)))
        XCTAssertEqual(Rewards.progress(hours: 10), 0.5, accuracy: 0.001)
        XCTAssertEqual(Rewards.progress(hours: 500), 1)
    }

    func testWelcomeBackGoesToTheFirstBlockAfterAMissedDay() {
        let days = Days(dayStartHour: 4)
        var first = record()
        first.day = 20261001
        first.startedAt = days.start(20261001).addingTimeInterval(3600)
        var back = record()
        back.day = 20261003
        back.startedAt = days.start(20261003).addingTimeInterval(3600)
        // (two blocks that day would earn the missed day back instead)
        let sessions = [first, back]
        let state = Streak.state(sessions, today: 20261003, days: days)
        XCTAssertEqual(state.status[20261002], .missed)
        XCTAssertEqual(Rewards.welcomeBackIDs(sessions, status: state.status, days: days), [back.id])
    }

    func testMinutesTodayIncludeUnfinishedBlocks() {
        let sessions = [record(25), record(12, outcome: .unfinished)]
        XCTAssertEqual(Rewards.minutes(on: 20261024, sessions), 37, accuracy: 0.001)
    }
}

final class StoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent("ember.json"))
    }

    func testRoundTrip() throws {
        let store = Store(root: root)
        store.data.prefs.goalMinutes = 150
        store.data.subjects = Fixtures.subjects
        store.data.sessions = [Fixtures.record(day: 20261024, start: Date(timeIntervalSince1970: 1_800_000_000), minutes: 25,
                                               subject: Fixtures.subjects[0].id, outcome: .completed, intent: "Q1")]
        store.saveNow()
        let (loaded, notice) = Store.load(from: root)
        XCTAssertNil(notice)
        XCTAssertEqual(loaded, store.data)
    }

    func testMissingFieldsFallBackToDefaults() throws {
        try write(#"{"prefs":{"goalMinutes":90,"timerStyle":"sparkles"}}"#)
        let (data, notice) = Store.load(from: root)
        XCTAssertNil(notice)
        XCTAssertEqual(data.prefs.goalMinutes, 90)
        XCTAssertEqual(data.prefs.timerStyle, .disc, "an unknown value falls back to the default")
        XCTAssertEqual(data.prefs.dayStartHour, 4)
        XCTAssertTrue(data.sessions.isEmpty)
    }

    func testABadRecordIsSkippedNotTheWholeFile() throws {
        let good = Fixtures.record(day: 20261024, start: Date(timeIntervalSince1970: 1_800_000_000), minutes: 25,
                                   subject: nil, outcome: .completed, intent: "")
        let goodJSON = String(data: try JSONEncoder.ember.encode(good), encoding: .utf8)!
        try write(#"{"sessions":[\#(goodJSON),{"day":"oops"},42]}"#)
        let (data, notice) = Store.load(from: root)
        XCTAssertNil(notice)
        XCTAssertEqual(data.sessions, [good])
    }

    func testAnUnreadableFileIsKeptAndTheNewestBackupLoads() throws {
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        var old = AppData()
        old.prefs.goalMinutes = 75
        try JSONEncoder.ember.encode(old).write(to: backups.appendingPathComponent("ember-20261020.json"))
        try JSONEncoder.ember.encode(AppData()).write(to: backups.appendingPathComponent("ember-20261019.json"))
        try write("this is not json")
        let (data, notice) = Store.load(from: root)
        XCTAssertEqual(data.prefs.goalMinutes, 75)
        XCTAssertNotNil(notice)
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("ember.corrupt-") })
        XCTAssertFalse(files.contains("ember.json"))
    }

    func testOneBackupPerDayKeepingSeven() throws {
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        for day in 10...19 {
            try Data("{}".utf8).write(to: backups.appendingPathComponent("ember-202610\(day).json"))
        }
        let store = Store(root: root)
        store.saveNow()        // creates ember.json; nothing to back up yet
        store.data.prefs.goalMinutes = 30
        let fresh = Store(root: root)
        fresh.saveNow()        // first save of the day for this instance: backs up, then prunes
        XCTAssertEqual(Store.backups(in: root).count, 7)
        XCTAssertTrue(Store.backups(in: root).first!.lastPathComponent.hasPrefix("ember-2026"))
    }
}
