import XCTest
@testable import Ember

final class CelebrationTests: XCTestCase {
    private let days = Days(dayStartHour: 4)
    private lazy var today = days.key(Date())

    private func block(_ dayOffset: Int, hour: Double = 10, minutes: Double = 25) -> SessionRecord {
        let day = days.adding(dayOffset, to: today)
        let start = days.start(day).addingTimeInterval(hour * 3600)
        return Fixtures.record(day: day, start: start, minutes: minutes, subject: nil, outcome: .completed, intent: "")
    }

    private func summary(history: [SessionRecord], new record: SessionRecord, goal: Int = 600) -> CompletionSummary {
        var data = AppData()
        data.prefs.goalMinutes = goal
        data.sessions = history + [record]
        return CompletionSummary.make(record: record, data: data)
    }

    func testTheFirstBlockOfTheDayExtendsTheStreak() {
        let s = summary(history: [block(-3), block(-2), block(-1)], new: block(0))
        XCTAssertTrue(s.extendedStreak)
        XCTAssertEqual(s.streakBefore, 3)
        XCTAssertEqual(s.streakAfter, 4)
        XCTAssertEqual(s.steps, [.complete, .streak])
        XCTAssertEqual(s.week.filter(\.isToday).first?.status, .credited)
    }

    func testASecondBlockTheSameDayOnlyGetsTheBlockScreen() {
        let s = summary(history: [block(-1), block(0, hour: 8)], new: block(0, hour: 10))
        XCTAssertFalse(s.extendedStreak)
        XCTAssertEqual(s.steps, [.complete])
    }

    func testReachingTheDailyGoal() {
        let s = summary(history: [block(0, hour: 8, minutes: 40)], new: block(0, hour: 10), goal: 60)
        XCTAssertTrue(s.goalReachedNow)
        XCTAssertEqual(s.steps, [.complete, .goal])
        let again = summary(history: [block(0, hour: 8, minutes: 70)], new: block(0, hour: 10), goal: 60)
        XCTAssertFalse(again.goalReachedNow, "the goal was already reached before this block")
    }

    func testARankUp() {
        let s = summary(history: [block(-1, minutes: 4.8 * 60)], new: block(0, hour: 10))
        XCTAssertEqual(s.rankBefore.name, "Spark")
        XCTAssertEqual(s.rankAfter.name, "Ember")
        XCTAssertTrue(s.steps.contains(.rankUp))
    }

    func testTheSeventhDayIsAMilestoneAndEarnsAFreeze() {
        let s = summary(history: (-6...(-1)).map { block($0) }, new: block(0))
        XCTAssertEqual(s.milestone, 7)
        XCTAssertTrue(s.freezeEarned)
        XCTAssertEqual(s.tierBefore, .glow)
        XCTAssertEqual(s.tierAfter, .blaze)
    }

    func testEarningBackAMissedDayShowsTheStreakScreen() {
        let history = [block(-4), block(-3), block(-2), block(0, hour: 8)]
        let s = summary(history: history, new: block(0, hour: 10))
        XCTAssertTrue(s.earnedBack)
        XCTAssertEqual(s.streakBefore, 1)
        XCTAssertEqual(s.streakAfter, 4)
        XCTAssertEqual(s.steps, [.complete, .streak])
    }

    func testTheVeryFirstBlock() {
        let s = summary(history: [], new: block(0))
        XCTAssertTrue(s.firstEver)
        XCTAssertEqual(s.streakAfter, 1)
    }

    func testAShortBlockDoesNotTouchTheStreak() {
        let s = summary(history: [block(-1)], new: block(0, minutes: 8))
        XCTAssertFalse(s.extendedStreak)
        XCTAssertEqual(s.streakAfter, 1)
    }
}
