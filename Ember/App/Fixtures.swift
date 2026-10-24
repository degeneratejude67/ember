import Foundation

/// Demo data and jump-to-screen states for the UI tests (`-uitest-seed`, `-uitest-screen`).
enum Fixtures {
    static var screen: String? { AppEnv.value(after: "-uitest-screen") }

    static let subjects: [StudySubject] = [
        StudySubject(name: "Heat Transfer", colorIndex: 0),
        StudySubject(name: "Fluid Machinery", colorIndex: 1),
        StudySubject(name: "IC Engines", colorIndex: 2),
        StudySubject(name: "Vibration", colorIndex: 3),
    ]

    /// With `-uitest-seed` (or a screen fixture): four subjects, two exams and 40 days of
    /// history ending in a 12-day streak, with today not yet done.
    static func seed() -> AppData? {
        guard AppEnv.arguments.contains("-uitest-seed") || screen != nil else { return nil }
        var data = AppData()
        data.prefs.onboarded = true
        data.prefs.goalMinutes = 120
        data.subjects = subjects
        data.prefs.subjectID = subjects[2].id
        if screen == "focus-ring" { data.prefs.timerStyle = .ring }
        if screen == "focus-digits" { data.prefs.timerStyle = .digits }
        let now = Date()
        data.exams = [
            Exam(subjectID: subjects[2].id, title: "IC Engines", at: now.addingTimeInterval(5 * 86_400 + 3_600)),
            Exam(subjectID: subjects[0].id, title: "Heat Transfer", at: now.addingTimeInterval(12 * 86_400)),
        ]
        let days = Days(dayStartHour: data.prefs.dayStartHour)
        let today = days.key(now)
        var sessions: [SessionRecord] = []
        // days 40...27 ago: an older streak; then a gap; then a 12-day streak up to yesterday
        let active = Array(27...40) + Array(1...12)
        for back in active {
            let day = days.adding(-back, to: today)
            let blocks = back % 3 == 0 ? 3 : 2
            for k in 0..<blocks {
                let start = days.start(day).addingTimeInterval(Double(5 + k) * 3_600)
                let subject = subjects[(back + k) % subjects.count]
                sessions.append(record(day: day, start: start, minutes: 25, subject: subject.id,
                                       outcome: .completed, intent: "Past paper question \(k + 1)"))
            }
            if back % 5 == 0 {
                let start = days.start(day).addingTimeInterval(9 * 3_600)
                var broken = record(day: day, start: start, minutes: 11, subject: subjects[1].id, outcome: .unfinished, intent: "")
                broken.distraction = back % 2 == 0 ? "YouTube" : "messages"
                sessions.append(broken)
            }
        }
        data.sessions = sessions
        return data
    }

    static func record(day: DayKey, start: Date, minutes: Double, subject: UUID?, outcome: Outcome, intent: String) -> SessionRecord {
        SessionRecord(day: day, startedAt: start, endedAt: start.addingTimeInterval(minutes * 60),
                      presetID: Preset.pomodoro.id, presetName: Preset.pomodoro.name, strictness: .deep,
                      subjectID: subject, intent: intent, round: 1, plannedMinutes: 25, minutes: minutes,
                      lockedMinutes: 0, slips: outcome == .completed ? 0 : 1, outcome: outcome,
                      reason: outcome == .completed ? .finished : .left, cleanBreak: outcome == .completed ? true : nil)
    }

    /// Puts the controller straight onto one screen.
    static func apply(_ screen: String, to controller: SessionController) {
        let prefs = Store.shared.data.prefs
        let config = SessionConfig(preset: prefs.preset, strictness: .deep, subjectID: prefs.subjectID,
                                   intent: "Finish the 2019 past paper, Q3", graceSeconds: 10,
                                   secondsPerMinute: 60, dayStartHour: prefs.dayStartHour)
        let now = Instant.now()
        switch screen {
        case "focus", "focus-ring", "focus-digits", "dimmed":
            var (session, _) = SessionEngine.start(config, now: now.adding(-12 * 60 - 25))
            session.round = 2
            controller.restore(session)
        case "flow":
            var flowConfig = config
            flowConfig.preset = .flow
            let (session, _) = SessionEngine.start(flowConfig, now: now.adding(-34 * 60))
            controller.restore(session)
        case "break", "ready":
            var (session, _) = SessionEngine.start(config, now: now.adding(-25 * 60 - 70))
            session.phase = .breakTime
            session.breakStart = now.adding(-70)
            session.breakSeconds = 5 * 60
            if screen == "ready" {
                session.phase = .ready
                session.breakStart = now.adding(-5 * 60 - 5)
                session.readySince = now.adding(-5)
            }
            session.parking = ["Email Dr Rahman about the lab report", "Look up the Dittus–Boelter range"]
            controller.restore(session)
        case "complete":
            // A summary that earns every screen: streak 13 to 14 (a milestone), the daily
            // goal, and a rank-up. -uitest-step picks the screen.
            let record = demoRecord(config, now: now)
            Store.shared.data.sessions.append(record)
            let real = CompletionSummary.make(record: record, data: Store.shared.data)
            controller.celebration = CompletionSummary(
                record: record, xp: 35, streakBefore: 13, streakAfter: 14, extendedStreak: true, milestone: 14,
                tierBefore: .blaze, tierAfter: .hot, freezeEarned: true, earnedBack: false,
                minutesBefore: 100, minutesAfter: 125, goal: 120,
                rankBefore: Rewards.ranks[2], rankAfter: Rewards.ranks[3], hoursAfter: 40.4,
                week: real.week, firstEver: false)
        case "exam-complete":
            var record = demoRecord(config, now: now)
            record.presetID = Preset.exam.id
            record.presetName = Preset.exam.name
            record.minutes = 180
            record.plannedMinutes = 180
            record.intent = ""
            Store.shared.data.sessions.append(record)
            controller.celebration = CompletionSummary.make(record: record, data: Store.shared.data)
        case "unfinished":
            var record = demoRecord(config, now: now)
            record.outcome = .unfinished
            record.reason = .left
            record.minutes = 18
            controller.unfinished = .init(record: record, awaySeconds: 72)
        default:
            break
        }
    }

    private static func demoRecord(_ config: SessionConfig, now: Instant) -> SessionRecord {
        let start = now.wall.addingTimeInterval(-25 * 60)
        return SessionRecord(day: Days(dayStartHour: config.dayStartHour).key(start), startedAt: start, endedAt: now.wall,
                             presetID: config.preset.id, presetName: config.preset.name, strictness: .deep,
                             subjectID: config.subjectID, intent: config.intent, round: 1, plannedMinutes: 25,
                             minutes: 25, lockedMinutes: 0, slips: 0, outcome: .completed, reason: .finished)
    }
}
