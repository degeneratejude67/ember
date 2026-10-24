import XCTest
@testable import Ember

final class StreakTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Dhaka")!
        return c
    }()
    private lazy var days = Days(dayStartHour: 4, calendar: calendar)
    private let base: DayKey = 20261001

    /// Blocks per day, by offset from `base`.
    private func history(_ blocks: [Int: Int]) -> [DayKey: Int] {
        Dictionary(uniqueKeysWithValues: blocks.map { (days.adding($0.key, to: base), $0.value) })
    }

    private func run(_ blocks: [Int: Int], today: Int) -> StreakState {
        Streak.replay(history(blocks), today: days.adding(today, to: base), days: days)
    }

    private func range(_ r: ClosedRange<Int>, _ n: Int = 1) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: r.map { ($0, n) })
    }

    // MARK: - Days

    func testTheStudyDayStartsAtFourInTheMorning() {
        let before = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 3, minute: 59))!
        let after = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 4, minute: 0))!
        XCTAssertEqual(days.key(before), 20261024)
        XCTAssertEqual(days.key(after), 20261025)
        let midnightStart = Days(dayStartHour: 0, calendar: calendar)
        XCTAssertEqual(midnightStart.key(before), 20261025)
        let sixStart = Days(dayStartHour: 6, calendar: calendar)
        XCTAssertEqual(sixStart.key(after), 20261024)
    }

    func testDayArithmeticAcrossMonthsYearsAndDaylightSaving() {
        XCTAssertEqual(days.adding(1, to: 20261031), 20261101)
        XCTAssertEqual(days.adding(1, to: 20261231), 20270101)
        XCTAssertEqual(days.adding(-1, to: 20260301), 20260228)
        XCTAssertEqual(days.distance(from: 20261225, to: 20270105), 11)
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let us = Days(dayStartHour: 4, calendar: newYork)
        XCTAssertEqual(us.adding(1, to: 20260307), 20260308)
        XCTAssertEqual(us.adding(1, to: 20260308), 20260309)
        XCTAssertEqual(us.adding(1, to: 20261031), 20261101)
        XCTAssertEqual(us.adding(1, to: 20261101), 20261102)
        XCTAssertEqual(us.distance(from: 20260301, to: 20260401), 31)
        let springNight = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 30))!
        XCTAssertEqual(us.key(springNight), 20260307)
    }

    func testWeekStartsOnMonday() {
        XCTAssertEqual(days.weekStart(20261024), 20261019) // Saturday -> Monday
        XCTAssertEqual(days.weekStart(20261019), 20261019)
        XCTAssertEqual(days.weekStart(20261025), 20261019) // Sunday
    }

    // MARK: - Streak

    func testNoHistory() {
        let state = run([:], today: 0)
        XCTAssertEqual(state.current, 0)
        XCTAssertEqual(state.best, 0)
        XCTAssertFalse(state.freshStart)
    }

    func testTodayIsNeverHeldAgainstTheStreak() {
        let state = run(range(0...4), today: 5)
        XCTAssertEqual(state.current, 5)
        XCTAssertFalse(state.todayDone)
        XCTAssertEqual(state.status[days.adding(5, to: base)], .pending)
        XCTAssertEqual(run(range(0...5), today: 5).current, 6)
    }

    func testAFreezeIsEarnedAtSevenDaysAndUsedOnAMiss() {
        var blocks = range(0...6)
        blocks[8] = 1
        let state = run(blocks, today: 8)
        XCTAssertEqual(state.status[days.adding(7, to: base)], .frozen)
        XCTAssertEqual(state.current, 8)
        XCTAssertEqual(state.freezes, 0)
    }

    func testAtMostTwoFreezes() {
        XCTAssertEqual(run(range(0...6), today: 6).freezes, 1)
        XCTAssertEqual(run(range(0...13), today: 13).freezes, 2)
        XCTAssertEqual(run(range(0...20), today: 20).freezes, 2)
    }

    func testTwoFreezesCoverTwoMissedDaysAndAThirdMissBreaks() {
        var blocks = range(0...13)
        blocks[16] = 1
        let survived = run(blocks, today: 16)
        XCTAssertEqual(survived.current, 15)
        blocks = range(0...13)
        blocks[17] = 1
        let broken = run(blocks, today: 17)
        XCTAssertEqual(broken.current, 1)
        XCTAssertEqual(broken.best, 14)
    }

    func testTwoBlocksTheNextDayEarnBackAMissedDay() {
        var blocks = range(0...4)
        blocks[6] = 2
        let state = run(blocks, today: 6)
        XCTAssertEqual(state.status[days.adding(5, to: base)], .repaired)
        XCTAssertEqual(state.current, 6)
    }

    func testEarnBackOfferWhileItIsStillPossible() {
        var blocks = range(0...4)
        blocks[6] = 1
        let state = run(blocks, today: 6)
        XCTAssertEqual(state.earnBack, StreakState.EarnBack(restores: 5, blocksToday: 1))
        XCTAssertEqual(state.earnBack?.left, 1)
        XCTAssertEqual(state.current, 1)
    }

    func testEarnBackFailsOnceTheDayIsOver() {
        var blocks = range(0...4)
        blocks[6] = 1
        blocks[7] = 1
        let state = run(blocks, today: 7)
        XCTAssertNil(state.earnBack)
        XCTAssertEqual(state.current, 2)
        XCTAssertEqual(state.best, 5)
    }

    func testTwoMissedDaysInARowCannotBeEarnedBack() {
        var blocks = range(0...4)
        blocks[7] = 2
        let state = run(blocks, today: 7)
        XCTAssertEqual(state.current, 1)
    }

    func testEarnBackAtMostOncePerFourteenDays() {
        var blocks = range(0...2)
        blocks[4] = 2
        blocks[5] = 1
        blocks[7] = 2
        let state = run(blocks, today: 7)
        XCTAssertEqual(state.status[days.adding(3, to: base)], .repaired)
        XCTAssertEqual(state.status[days.adding(6, to: base)], .missed)
        XCTAssertNil(state.earnBack)
        XCTAssertEqual(state.current, 1)
    }

    func testAFreezeIsUsedBeforeAnEarnBack() {
        var blocks = range(0...6)
        blocks[8] = 2
        let state = run(blocks, today: 8)
        XCTAssertEqual(state.status[days.adding(7, to: base)], .frozen)
    }

    func testFreshStartAfterAStreakEnds() {
        var blocks = range(0...9)
        blocks[13] = 0
        let state = run(blocks, today: 13)
        XCTAssertEqual(state.current, 0)
        XCTAssertTrue(state.freshStart)
        XCTAssertEqual(state.best, 10)
    }

    func testMilestones() {
        XCTAssertEqual(Streak.milestone(from: 2, to: 3), 3)
        XCTAssertEqual(Streak.milestone(from: 6, to: 7), 7)
        XCTAssertNil(Streak.milestone(from: 7, to: 8))
        XCTAssertEqual(Streak.milestone(from: 364, to: 365), 365)
        XCTAssertEqual(Streak.milestone(from: 399, to: 400), 400)
        XCTAssertNil(Streak.milestone(from: 400, to: 401))
        XCTAssertEqual(Streak.milestone(from: 0, to: 1), nil)
    }

    func testWhichBlocksQualify() {
        func record(_ minutes: Double, _ outcome: Outcome) -> SessionRecord {
            Fixtures.record(day: base, start: Date(), minutes: minutes, subject: nil, outcome: outcome, intent: "")
        }
        XCTAssertFalse(record(9.9, .completed).qualifies)
        XCTAssertTrue(record(10, .completed).qualifies)
        XCTAssertFalse(record(50, .unfinished).qualifies)
        XCTAssertTrue(record(12, .interrupted).qualifies)
        let counts = Streak.qualifying([record(25, .completed), record(25, .completed), record(30, .unfinished)])
        XCTAssertEqual(counts[base], 2)
    }
}
