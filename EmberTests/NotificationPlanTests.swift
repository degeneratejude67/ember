import XCTest
@testable import Ember

final class NotificationPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Dhaka")!
        return c
    }()
    private lazy var days = Days(dayStartHour: 4, calendar: calendar)

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func data(studied: [(day: Int, hour: Int)]) -> AppData {
        var data = AppData()
        data.sessions = studied.map { d, h in
            let start = at(d, h)
            return Fixtures.record(day: days.key(start), start: start, minutes: 25, subject: nil, outcome: .completed, intent: "")
        }
        return data
    }

    func testTwoRemindersOnADayWithoutABlock() {
        let plan = NotificationPlan.plan(data(studied: [(23, 17)]), now: at(24, 9), expiry: nil, calendar: calendar)
        let today = plan.filter { $0.id.hasPrefix("r.20261024.") }
        XCTAssertEqual(today.map(\.id), ["r.20261024.first", "r.20261024.last"])
        XCTAssertEqual(today[0].date, at(24, 17), "at the time he started yesterday")
        XCTAssertEqual(today[1].date, at(24, 22))
        XCTAssertTrue(today[0].body.contains("1-day streak"), today[0].body)
    }

    func testNoRemindersOnceTodayIsDone() {
        let plan = NotificationPlan.plan(data(studied: [(23, 17), (24, 8)]), now: at(24, 9), expiry: nil, calendar: calendar)
        XCTAssertFalse(plan.contains { $0.id.hasPrefix("r.20261024.") })
        XCTAssertTrue(plan.contains { $0.id == "r.20261025.first" })
    }

    func testOnlyFutureTimesAndAtMostTwoADay() {
        let plan = NotificationPlan.plan(data(studied: [(23, 17)]), now: at(24, 21), expiry: nil, calendar: calendar)
        XCTAssertEqual(plan.filter { $0.id.hasPrefix("r.20261024.") }.map(\.id), ["r.20261024.last"])
        XCTAssertTrue(plan.allSatisfy { $0.date > at(24, 21) })
        XCTAssertLessThanOrEqual(plan.count, 2 * NotificationPlan.daysAhead)
    }

    func testALateUsualStartMovesToEightPM() {
        let plan = NotificationPlan.plan(data(studied: [(24, 1)]), now: at(24, 9), expiry: nil, calendar: calendar)
        XCTAssertEqual(plan.first { $0.id == "r.20261024.first" }?.date, at(24, 20))
    }

    func testEarnBackDayWording() {
        let plan = NotificationPlan.plan(data(studied: [(20, 9), (21, 9), (22, 9)]), now: at(24, 8), expiry: nil, calendar: calendar)
        XCTAssertTrue(plan.first { $0.id == "r.20261024.first" }!.body.contains("bring back your 3-day streak"))
    }

    func testResignReminderTheEveningBefore() {
        let expiry = at(29, 21, 27)
        let plan = NotificationPlan.plan(AppData(), now: at(24, 9), expiry: expiry, calendar: calendar)
        XCTAssertEqual(plan.first { $0.id == "r.resign" }?.date, at(28, 19))
        let late = NotificationPlan.plan(AppData(), now: at(28, 20), expiry: expiry, calendar: calendar)
        XCTAssertEqual(late.first { $0.id == "r.resign" }?.date, at(29, 19, 27), "two hours before when the evening has passed")
    }

    func testRemindersOffKeepsOnlyTheResignReminder() {
        var quiet = data(studied: [(23, 17)])
        quiet.prefs.remindersOn = false
        let plan = NotificationPlan.plan(quiet, now: at(24, 9), expiry: at(29, 21), calendar: calendar)
        XCTAssertEqual(plan.map(\.id), ["r.resign"])
    }
}
