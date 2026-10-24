import XCTest
@testable import Ember

/// The session state machine, driven with fake instants.
final class EngineTests: XCTestCase {
    private let t0 = Instant(wall: Date(timeIntervalSince1970: 1_800_000_000), mono: 1_000)

    private func at(_ seconds: Double) -> Instant { t0.adding(seconds) }

    private func config(_ preset: Preset = .pomodoro, strictness: Strictness = .deep, grace: Double = 10) -> SessionConfig {
        SessionConfig(preset: preset, strictness: strictness, subjectID: nil, intent: "Q3", graceSeconds: grace,
                      secondsPerMinute: 60, dayStartHour: 4)
    }

    private func started(_ c: SessionConfig? = nil, round: Int = 1) -> ActiveSession? {
        SessionEngine.start(c ?? config(), now: t0, round: round).0
    }

    @discardableResult
    private func send(_ state: inout ActiveSession?, _ event: SessionEvent, _ seconds: Double) -> [Effect] {
        SessionEngine.reduce(&state, event, now: at(seconds))
    }

    private func records(_ effects: [Effect]) -> [SessionRecord] {
        effects.compactMap { if case let .record(r) = $0 { return r } else { return nil } }
    }

    private func cleanFlags(_ effects: [Effect]) -> [Bool] {
        effects.compactMap { if case let .updateRecord(_, clean) = $0 { return clean } else { return nil } }
    }

    // MARK: - Completion and breaks

    func testPomodoroCompletesAtItsPlannedEndAndStartsTheBreak() {
        var s = started()
        let effects = send(&s, .tick, 25 * 60 + 3)
        let record = try! XCTUnwrap(records(effects).first)
        XCTAssertEqual(record.outcome, .completed)
        XCTAssertEqual(record.minutes, 25, accuracy: 0.001)
        XCTAssertEqual(record.endedAt, at(1500).wall)
        XCTAssertTrue(effects.contains(.celebrate(record)))
        XCTAssertEqual(s?.phase, .breakTime)
        XCTAssertEqual(s?.breakStart, at(1500))
        XCTAssertEqual(s?.breakSeconds, 300)
    }

    func testLongBreakAfterTheFourthRound() {
        var s = started(round: 4)
        send(&s, .tick, 1501)
        XCTAssertEqual(s?.breakSeconds, 900)
    }

    func testBreakEndsOnTheReadyScreenAndCountsAsClean() {
        var s = started()
        send(&s, .tick, 1501)
        let effects = send(&s, .tick, 1801)
        XCTAssertEqual(s?.phase, .ready)
        XCTAssertEqual(cleanFlags(effects), [true])
        XCTAssertTrue(effects.contains(.play(.breakEnd)))
    }

    func testLeavingDuringTheBreakMakesItNotClean() {
        var s = started()
        send(&s, .tick, 1501)
        send(&s, .inactive, 1600)
        send(&s, .background, 1600.5)
        send(&s, .active, 1700)
        XCTAssertEqual(s?.breakDirty, true)
        XCTAssertEqual(cleanFlags(send(&s, .tick, 1801)), [false])
    }

    func testLockingDuringTheBreakIsStillClean() {
        var s = started()
        send(&s, .tick, 1501)
        send(&s, .inactive, 1600)
        send(&s, .lock(.darwin, at: at(1600.3)), 1600.3)
        send(&s, .background, 1600.5)
        send(&s, .active, 1700)
        XCTAssertEqual(cleanFlags(send(&s, .tick, 1801)), [true])
    }

    func testSkippingTheBreakIsNotClean() {
        var s = started()
        send(&s, .tick, 1501)
        let effects = send(&s, .skipBreak, 1600)
        XCTAssertEqual(s?.phase, .ready)
        XCTAssertEqual(cleanFlags(effects), [false])
    }

    func testExtendingTheBreakAddsTwoMinutes() {
        var s = started()
        send(&s, .tick, 1501)
        send(&s, .extendBreak, 1600)
        XCTAssertEqual(s?.breakSeconds, 420)
    }

    func testStartingTheNextRound() {
        var s = started()
        send(&s, .tick, 1501)
        send(&s, .tick, 1801)
        send(&s, .startNextRound, 2000)
        XCTAssertEqual(s?.phase, .focus)
        XCTAssertEqual(s?.round, 2)
        XCTAssertEqual(s?.blockStart, at(2000))
    }

    func testTheReadyScreenTimesOutAfterThirtyMinutes() {
        var s = started()
        send(&s, .tick, 1501)
        send(&s, .tick, 1801)
        send(&s, .tick, 1800 + 30 * 60 + 1)
        XCTAssertNil(s)
    }

    // MARK: - Leaving

    func testAQuickTripAwayIsASlip() {
        var s = started()
        send(&s, .inactive, 100)
        send(&s, .background, 100.2)
        send(&s, .active, 105)
        XCTAssertEqual(s?.isFocusing, true)
        XCTAssertEqual(s?.slips, 1)
    }

    func testInactiveOnlyIsNotLeaving() {
        var s = started()
        send(&s, .inactive, 100)
        send(&s, .active, 200)
        XCTAssertEqual(s?.isFocusing, true)
        XCTAssertEqual(s?.slips, 0)
    }

    func testLeavingTooLongEndsTheBlockCountingUpToTheMomentHeLeft() {
        var s = started()
        send(&s, .inactive, 600)
        send(&s, .background, 600)
        let effects = send(&s, .active, 700)
        XCTAssertNil(s)
        let record = try! XCTUnwrap(records(effects).first)
        XCTAssertEqual(record.outcome, .unfinished)
        XCTAssertEqual(record.reason, .left)
        XCTAssertEqual(record.minutes, 10, accuracy: 0.001)
        XCTAssertTrue(effects.contains(.unfinished(record, awaySeconds: 100)))
        XCTAssertTrue(effects.contains(.play(.fizzle)))
    }

    func testLeavingSchedulesTheNudge() {
        var s = started()
        send(&s, .inactive, 100)
        let effects = send(&s, .background, 101)
        XCTAssertTrue(effects.contains(.schedule(.nudge, at: at(104).wall)))
    }

    func testADarwinLockAtTheMomentOfLeavingProtectsTheBlock() {
        var s = started()
        send(&s, .inactive, 300)
        send(&s, .lock(.darwin, at: at(300.5)), 300.5)
        let effects = send(&s, .background, 300.6)
        XCTAssertFalse(effects.contains { if case .schedule(.nudge, _) = $0 { return true } else { return false } })
        send(&s, .active, 900)
        XCTAssertEqual(s?.isFocusing, true)
        XCTAssertEqual(s?.slips, 0)
    }

    func testALateDarwinLockMeansHeLeftFirst() {
        var s = started()
        send(&s, .inactive, 300)
        send(&s, .background, 300.2)
        send(&s, .lock(.darwin, at: at(305)), 305)
        send(&s, .active, 400)
        XCTAssertNil(s)
    }

    func testProtectedDataGoingAwayWithinThirteenSecondsMeansALock() {
        var s = started()
        send(&s, .inactive, 300)
        let effects = send(&s, .background, 300.2)
        XCTAssertTrue(effects.contains { if case .schedule(.nudge, _) = $0 { return true } else { return false } })
        XCTAssertTrue(send(&s, .lock(.protectedData, at: at(310.4)), 310.4).contains(.cancel([.nudge])))
        send(&s, .active, 900)
        XCTAssertEqual(s?.isFocusing, true)
    }

    func testProtectedDataGoingAwayLaterDoesNotCount() {
        var s = started()
        send(&s, .inactive, 300)
        send(&s, .background, 300.2)
        send(&s, .lock(.protectedData, at: at(320)), 320)
        send(&s, .active, 400)
        XCTAssertNil(s)
    }

    func testABlockThatWouldEndWithinTheGraceTimeStillCompletes() {
        var s = started()
        send(&s, .background, 1495)
        let effects = send(&s, .active, 1600)
        let record = try! XCTUnwrap(records(effects).first)
        XCTAssertEqual(record.outcome, .completed)
        XCTAssertEqual(record.endedAt, at(1500).wall)
    }

    func testABlockThatEndedBeforeHeLeftCompletes() {
        var s = started()
        send(&s, .background, 1510)
        let record = try! XCTUnwrap(records(send(&s, .active, 1600)).first)
        XCTAssertEqual(record.outcome, .completed)
    }

    func testLockedAwayTheBlockCompletesAndTheBreakRunsOut() {
        var s = started()
        send(&s, .inactive, 300)
        send(&s, .lock(.darwin, at: at(300.2)), 300.2)
        send(&s, .background, 300.3)
        let effects = send(&s, .active, 2000)
        XCTAssertEqual(records(effects).first?.outcome, .completed)
        XCTAssertEqual(s?.phase, .ready)
        XCTAssertFalse(effects.contains(.play(.breakEnd)), "the break ended long ago; its notification already rang")
    }

    func testRelaxedModeNeverPenalisesLeaving() {
        var s = started(config(strictness: .relaxed))
        let effects = send(&s, .background, 100)
        XCTAssertFalse(effects.contains { if case .schedule(.nudge, _) = $0 { return true } else { return false } })
        send(&s, .active, 1000)
        XCTAssertEqual(s?.isFocusing, true)
        XCTAssertEqual(s?.slips, 0)
    }

    // MARK: - Relaunch

    func testRelaunchAfterLeavingCountsAsLeft() {
        var s = started()
        send(&s, .inactive, 100)
        send(&s, .background, 100.1)
        let effects = send(&s, .relaunch, 200)
        XCTAssertNil(s)
        XCTAssertEqual(records(effects).first?.reason, .left)
    }

    func testRelaunchAfterALockIsSafe() {
        var s = started()
        send(&s, .inactive, 100)
        send(&s, .lock(.darwin, at: at(100.3)), 100.3)
        send(&s, .background, 100.4)
        send(&s, .relaunch, 500)
        XCTAssertEqual(s?.isFocusing, true)
    }

    func testForceQuitFromTheAppSwitcherCountsAsLeaving() {
        var s = started()
        send(&s, .inactive, 100)
        send(&s, .relaunch, 130)
        XCTAssertNil(s)
    }

    func testACrashWithAFreshHeartbeatResumes() {
        var s = started()
        send(&s, .relaunch, 60)
        XCTAssertEqual(s?.isFocusing, true)
    }

    func testACrashWithAStaleHeartbeatKeepsTheMinutesAsInterrupted() {
        var s = started()
        s?.heartbeat = at(300)
        let effects = send(&s, .relaunch, 900)
        XCTAssertNil(s)
        let record = try! XCTUnwrap(records(effects).first)
        XCTAssertEqual(record.outcome, .interrupted)
        XCTAssertEqual(record.minutes, 5, accuracy: 0.001)
        XCTAssertFalse(record.qualifies, "5 minutes is under the 10-minute streak rule")
    }

    // MARK: - Pausing and giving up

    func testDeepFocusPausesOnceAndResumesByItself() {
        var s = started()
        send(&s, .pause, 100)
        XCTAssertEqual(s?.phase, .paused)
        send(&s, .tick, 100 + 121)
        XCTAssertEqual(s?.phase, .focus)
        XCTAssertEqual(s?.pausedSeconds, 120)
        XCTAssertFalse(SessionEngine.canPause(s!))
        XCTAssertEqual(records(send(&s, .tick, 1500 + 121)).first?.outcome, .completed)
    }

    func testRelaxedPausesAsOftenAsNeeded() {
        var s = started(config(strictness: .relaxed))
        send(&s, .pause, 100)
        send(&s, .resume, 400)
        XCTAssertEqual(s?.pausedSeconds, 300)
        XCTAssertTrue(SessionEngine.canPause(s!))
    }

    func testGivingUpRecordsAnUnfinishedBlock() {
        var s = started()
        let record = try! XCTUnwrap(records(send(&s, .giveUp, 420)).first)
        XCTAssertNil(s)
        XCTAssertEqual(record.reason, .gaveUp)
        XCTAssertEqual(record.minutes, 7, accuracy: 0.001)
    }

    // MARK: - Flowtime, Just 5 minutes, mock exams

    func testFlowtimeBreakIsAFifthOfTheFocus() {
        var s = started(config(.flow))
        let record = try! XCTUnwrap(records(send(&s, .finish, 40 * 60)).first)
        XCTAssertNil(record.plannedMinutes)
        XCTAssertEqual(record.minutes, 40, accuracy: 0.001)
        XCTAssertEqual(s?.breakSeconds, 8 * 60)
    }

    func testFlowtimeBreaksStayBetweenFiveAndThirtyMinutes() {
        var short = started(config(.flow))
        send(&short, .finish, 10 * 60)
        XCTAssertEqual(short?.breakSeconds, 5 * 60)
        var long = started(config(.flow))
        let record = try! XCTUnwrap(records(send(&long, .tick, 181 * 60)).first)
        XCTAssertEqual(record.minutes, 180, accuracy: 0.001)
        XCTAssertEqual(long?.breakSeconds, 30 * 60)
    }

    func testJustFiveMinutesTurnsIntoFlowtime() {
        var s = started(config(.starter))
        let effects = send(&s, .tick, 301)
        XCTAssertEqual(s?.kind, .flow)
        XCTAssertEqual(s?.starterConverted, true)
        XCTAssertNil(s?.plannedSeconds)
        XCTAssertTrue(effects.contains(.play(.cue)))
        let record = try! XCTUnwrap(records(send(&s, .finish, 900)).first)
        XCTAssertEqual(record.minutes, 15, accuracy: 0.001)
        XCTAssertEqual(s?.breakSeconds, 5 * 60)
    }

    func testMockExamTimeChecksAndNoBreak() {
        var s = started(config(.exam))
        XCTAssertTrue(send(&s, .tick, 5400 + 1).contains(.play(.cue)))
        XCTAssertEqual(s?.cuesDone, ["half"])
        XCTAssertTrue(send(&s, .tick, 9900 + 1).contains(.play(.cue)))
        let record = try! XCTUnwrap(records(send(&s, .tick, 10_800 + 1)).first)
        XCTAssertEqual(record.minutes, 180, accuracy: 0.001)
        XCTAssertNil(s, "a mock exam has no break")
    }

    func testATimeCheckCrossedLongAgoStaysSilent() {
        var s = started(config(.exam))
        let effects = send(&s, .tick, 6000)
        XCTAssertFalse(effects.contains(.play(.cue)))
        XCTAssertEqual(s?.cuesDone, ["half"])
    }

    // MARK: - Records

    func testABlockCountsForTheStudyDayItStartedIn() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 3, minute: 40))!
        let (session, _) = SessionEngine.start(config(), now: Instant(wall: start, mono: 50))
        var s: ActiveSession? = session
        let record = try! XCTUnwrap(records(SessionEngine.reduce(&s, .tick, now: Instant(wall: start.addingTimeInterval(1501), mono: 1551))).first)
        XCTAssertEqual(record.day, 20261024)
    }

    func testGuidedAccessMinutesAreRecorded() {
        var s = started()
        send(&s, .guidedAccess(true), 300)
        send(&s, .guidedAccess(false), 900)
        let record = try! XCTUnwrap(records(send(&s, .tick, 1501)).first)
        XCTAssertEqual(record.lockedMinutes, 10, accuracy: 0.001)
    }

    func testParkingItemsTravelWithTheBlock() {
        var s = started()
        send(&s, .addParking("  Email the lab TA  "), 100)
        send(&s, .addParking("   "), 110)
        XCTAssertEqual(s?.parking, ["Email the lab TA"])
        XCTAssertEqual(records(send(&s, .tick, 1501)).first?.parking, ["Email the lab TA"])
    }
}
