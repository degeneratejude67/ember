import Foundation

/// What a session was started with.
struct SessionConfig: Codable, Equatable {
    var preset: Preset
    var strictness: Strictness
    var subjectID: UUID?
    var intent: String
    var graceSeconds: Double
    /// 60 normally; 1 under `-uitest-fast`, where preset minutes become seconds.
    var secondsPerMinute: Double
    var dayStartHour: Int
    /// Studying inside another app (CollaNote, Slate...): time away from Ember counts as
    /// focus, and Focus Guard bounces count as slips.
    var studyAppID: String?
    /// The course topic for this block.
    var topicID: UUID?

    var studiesElsewhere: Bool { studyAppID != nil }
    /// From 2 minutes of allowed time away, Ember checks in instead of ending the block.
    var checksIn: Bool { graceSeconds >= 120 }
}

enum SessionPhase: String, Codable {
    case focus, paused, breakTime, ready
}

enum LockSource: String, Codable {
    /// SpringBoard's com.apple.springboard.lockcomplete, right at the lock.
    case darwin
    /// Protected data became unavailable, about 10 s after a lock.
    case protectedData
}

/// One absence while a block or break runs.
struct AwayRecord: Codable, Equatable {
    var inactiveAt: Instant?
    var backgroundAt: Instant?
    var lockedAt: Instant?
    var lockSource: LockSource?
    /// He answered "Still studying?" here; the allowed time away starts again from this moment.
    var checkedInAt: Instant?
    /// Studying in another app: Focus Guard saw a distracting app open here, which starts the
    /// allowed time.
    var distractedAt: Instant?
}

/// The running session, saved to active.json on every change so a relaunch can pick it up.
struct ActiveSession: Codable, Equatable {
    /// Id of the current block; becomes the record's id.
    var id = UUID()
    var config: SessionConfig
    var phase: SessionPhase = .focus
    /// The preset's kind, except that "Just 5 minutes" turns into Flowtime.
    var kind: PresetKind
    var round = 1
    var blockStart: Instant
    /// Planned focus in real seconds; nil while counting up.
    var plannedSeconds: Double?
    var pausedSeconds = 0.0
    var pausedAt: Instant?
    var pausesUsed = 0
    var slips = 0
    var away: AwayRecord?
    var breakStart: Instant?
    var breakSeconds: Double?
    /// He left Ember during the break, or cut it short.
    var breakDirty = false
    var readySince: Instant?
    var cuesDone: [String] = []
    var starterConverted = false
    var lockedSeconds = 0.0
    var lockedSince: Instant?
    var parking: [String] = []
    var heartbeat: Instant
    /// The block whose break is running, so its clean-break flag can be set when it ends.
    var lastRecordID: UUID?

    var isFocusing: Bool { phase == .focus || phase == .paused }
}

enum SessionEvent: Equatable {
    case tick
    case pause, resume
    case giveUp
    /// Flowtime's Finish.
    case finish
    case startNextRound
    case extendBreak, skipBreak
    /// Ends the session from a break or the ready screen.
    case stop
    case inactive, background, active
    case lock(LockSource, at: Instant)
    case guidedAccess(Bool)
    /// The app started with a saved session.
    case relaunch
    case addParking(String)
    /// Focus Guard saw a distracting app (YouTube, games) open.
    case distracted(at: Instant)
    /// He answered "I'm still studying" to the check-in.
    case checkIn
}

/// Local notifications owned by the session; the raw value is the request identifier.
enum SessionNotice: String, CaseIterable {
    case blockEnd = "s.end"
    case breakEnd = "s.break"
    case nudge = "s.nudge"
    case half = "s.cue.half"
    case last15 = "s.cue.15"
    case starter = "s.starter"
    case pauseOver = "s.pause"
    /// "Still studying?" when the allowed time away is up.
    case checkIn = "s.checkin"
    /// The block ended because the check-in got no answer.
    case awayEnd = "s.away"

    static let block: [SessionNotice] = [.blockEnd, .half, .last15, .starter, .pauseOver, .checkIn, .awayEnd]
    static let away: [SessionNotice] = [.nudge, .checkIn, .awayEnd]
}

/// What the controller must do after an event.
enum Effect: Equatable {
    case save
    case record(SessionRecord)
    case updateRecord(UUID, cleanBreak: Bool)
    case celebrate(SessionRecord)
    case unfinished(SessionRecord, awaySeconds: Double?)
    case play(SoundEffect)
    case schedule(SessionNotice, at: Date)
    case cancel([SessionNotice])
    case keepAwake(Bool)
}

/// The session state machine, as pure functions of (state, event, time). All timing comes
/// from the instants passed in, so the unit tests drive it with a fake clock.
enum SessionEngine {
    /// A Deep Focus pause resumes by itself after this many real seconds.
    static let pauseLimit = 120.0
    /// The ready screen gives up after 30 minutes and the cycle starts over.
    static let readyTimeout = 30 * 60.0
    static let flowCapMinutes = 180.0
    static let darwinWindow = 2.0
    static let protectedWindow = 13.0
    static let nudgeDelay = 3.0
    /// How long the check-in waits for an answer before the block ends.
    static let checkInWindow = 60.0
    /// Cues and chimes play only if they were crossed this recently (otherwise a notification
    /// already rang).
    static let cueWindow = 3.0
    /// Without an away record, a saved session older than this was killed by a crash or a
    /// flat battery.
    static let heartbeatStale = 120.0

    // MARK: - Start

    static func start(_ config: SessionConfig, now: Instant, round: Int = 1) -> (ActiveSession, [Effect]) {
        var session = ActiveSession(config: config, kind: config.preset.kind, round: round, blockStart: now, heartbeat: now)
        switch session.kind {
        case .flow: session.plannedSeconds = nil
        default: session.plannedSeconds = Double(config.preset.focusMinutes) * config.secondsPerMinute
        }
        var effects: [Effect] = [.play(.start), .keepAwake(true)]
        effects += schedule(session, now: now)
        effects.append(.save)
        return (session, effects)
    }

    // MARK: - Reading the state

    /// Focus time so far in real seconds, not counting pauses. A Deep Focus pause stops
    /// counting as a pause after `pauseLimit`.
    static func focusElapsed(_ s: ActiveSession, at t: Instant) -> Double {
        var paused = s.pausedSeconds
        if let p = s.pausedAt {
            let current = p.seconds(to: t)
            paused += s.config.strictness == .relaxed ? current : min(current, pauseLimit)
        }
        return max(0, s.blockStart.seconds(to: t) - paused)
    }

    static func remaining(_ s: ActiveSession, at t: Instant) -> Double? {
        s.plannedSeconds.map { max(0, $0 - focusElapsed(s, at: t)) }
    }

    static func breakRemaining(_ s: ActiveSession, at t: Instant) -> Double {
        guard let start = s.breakStart, let length = s.breakSeconds else { return 0 }
        return max(0, length - start.seconds(to: t))
    }

    static func canPause(_ s: ActiveSession) -> Bool {
        s.phase == .focus && (s.config.strictness == .relaxed || s.pausesUsed < 1)
    }

    static func lockedSeconds(_ s: ActiveSession, at t: Instant) -> Double {
        s.lockedSeconds + (s.lockedSince.map { $0.seconds(to: t) } ?? 0)
    }

    // MARK: - Events

    static func reduce(_ state: inout ActiveSession?, _ event: SessionEvent, now: Instant) -> [Effect] {
        guard var s = state else { return [] }
        var effects: [Effect] = []

        switch event {
        case .tick:
            break

        case .pause:
            guard canPause(s) else { return [] }
            s.phase = .paused
            s.pausedAt = now
            s.pausesUsed += 1
            effects.append(.cancel(SessionNotice.block))
            if s.config.strictness != .relaxed {
                effects.append(.schedule(.pauseOver, at: now.wall.addingTimeInterval(pauseLimit)))
            }
            effects.append(.save)

        case .resume:
            guard s.phase == .paused else { return [] }
            resume(&s, at: now)
            effects.append(.cancel([.pauseOver]))
            effects += schedule(s, now: now)
            effects.append(.save)

        case .giveUp:
            guard s.isFocusing else { return [] }
            state = nil
            return fail(s, reason: .gaveUp, countedUntil: now, awaySeconds: nil)

        case .finish:
            guard s.isFocusing, s.plannedSeconds == nil else { return [] }
            if s.phase == .paused { resume(&s, at: now) }
            state = s
            return complete(&state, at: now, now: now)

        case .startNextRound:
            guard s.phase == .ready || s.phase == .breakTime else { return [] }
            effects += closeBreak(&s, clean: s.phase == .ready && !s.breakDirty)
            effects.append(.cancel([.breakEnd]))
            let (next, startEffects) = start(s.config, now: now, round: s.round + 1)
            state = next
            return effects + startEffects

        case .extendBreak:
            let extra = 2 * s.config.secondsPerMinute
            if s.phase == .breakTime {
                s.breakSeconds = (s.breakSeconds ?? 0) + extra
            } else if s.phase == .ready {
                s.phase = .breakTime
                s.breakStart = now
                s.breakSeconds = extra
                s.readySince = nil
            } else {
                return []
            }
            if let start = s.breakStart, let length = s.breakSeconds {
                effects.append(.schedule(.breakEnd, at: start.wall.addingTimeInterval(length)))
            }
            effects.append(.save)

        case .skipBreak:
            guard s.phase == .breakTime else { return [] }
            s.breakDirty = true
            s.phase = .ready
            s.readySince = now
            effects += closeBreak(&s, clean: false)
            effects += [.cancel([.breakEnd]), .save]

        case .stop:
            guard !s.isFocusing else { return [] }
            effects += closeBreak(&s, clean: s.phase == .ready && !s.breakDirty)
            state = nil
            return effects + [.cancel(SessionNotice.allCases), .keepAwake(false), .save]

        case .inactive:
            if (s.isFocusing || s.phase == .breakTime) && s.away == nil {
                s.away = AwayRecord(inactiveAt: now)
            }

        case .background:
            guard s.isFocusing || s.phase == .breakTime else { break }
            var away = s.away ?? AwayRecord(inactiveAt: now)
            away.backgroundAt = now
            s.away = away
            if s.isFocusing && s.config.strictness.polices && away.lockedAt == nil && !s.config.studiesElsewhere {
                if s.config.checksIn {
                    effects += checkInNotices(from: away.checkedInAt ?? now, s)
                } else {
                    effects.append(.schedule(.nudge, at: now.wall.addingTimeInterval(nudgeDelay)))
                }
            }
            effects.append(.save)

        case let .lock(source, at):
            guard var away = s.away, away.lockedAt == nil else { return [] }
            guard accepts(source, at: at, away: away) else { return [] }
            away.lockedAt = at
            away.lockSource = source
            s.away = away
            effects += [.cancel(SessionNotice.away), .save]

        case .active:
            effects.append(.cancel(SessionNotice.away))
            if let away = s.away {
                s.away = nil
                state = s
                effects += judge(&state, away: away, now: now, relaunch: false)
                guard let judged = state else { return effects }
                s = judged
            }

        case .relaunch:
            if let away = s.away {
                s.away = nil
                state = s
                effects += judge(&state, away: away, now: now, relaunch: true)
                guard let judged = state else { return effects }
                s = judged
            } else if s.isFocusing && s.heartbeat.seconds(to: now) > heartbeatStale {
                state = nil
                return interrupted(s, until: s.heartbeat)
            }

        case let .guidedAccess(on):
            if on && s.lockedSince == nil && s.isFocusing {
                s.lockedSince = now
            } else if !on, let since = s.lockedSince {
                s.lockedSeconds += since.seconds(to: now)
                s.lockedSince = nil
            }
            effects.append(.save)

        case let .distracted(at):
            guard s.isFocusing else { return [] }
            s.slips += 1
            if s.config.studiesElsewhere, s.config.checksIn, var away = s.away {
                // a check-in after the last distraction cleared it
                let cleared = away.checkedInAt.map { checked in away.distractedAt.map { checked.mono > $0.mono } ?? true } ?? false
                if away.distractedAt == nil || cleared {
                    away.distractedAt = at
                    s.away = away
                    effects += checkInNotices(from: at, s)
                }
            }
            effects.append(.save)

        case .checkIn:
            guard s.isFocusing, var away = s.away else { return [] }
            away.checkedInAt = now
            s.away = away
            effects.append(.cancel([.checkIn, .awayEnd]))
            if !s.config.studiesElsewhere && s.config.checksIn {
                effects += checkInNotices(from: now, s)
            }
            effects.append(.save)

        case let .addParking(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            s.parking.append(trimmed)
            effects.append(.save)
        }

        state = s
        return effects + advance(&state, now: now)
    }

    /// Catches up with the clock: pause limits, "Just 5 minutes" turning into Flowtime,
    /// exam time checks, the end of a block or break, and the ready screen timing out.
    /// Safe to call any number of times.
    static func advance(_ state: inout ActiveSession?, now: Instant) -> [Effect] {
        guard var s = state else { return [] }
        var effects: [Effect] = []
        let spm = s.config.secondsPerMinute

        if s.phase == .paused, s.config.strictness != .relaxed, let p = s.pausedAt, p.seconds(to: now) >= pauseLimit {
            s.pausedSeconds += pauseLimit
            s.pausedAt = nil
            s.phase = .focus
            if p.adding(pauseLimit).seconds(to: now) <= cueWindow { effects.append(.play(.cue)) }
            effects.append(.cancel([.pauseOver]))
            effects += schedule(s, now: now)
            effects.append(.save)
        }

        if s.phase == .focus {
            let elapsed = focusElapsed(s, at: now)
            if s.kind == .starter, let planned = s.plannedSeconds, elapsed >= planned {
                s.kind = .flow
                s.plannedSeconds = nil
                s.starterConverted = true
                if elapsed - planned <= cueWindow { effects.append(.play(.cue)) }
                effects.append(.cancel([.starter]))
                effects += schedule(s, now: now)
                effects.append(.save)
            }
            if s.kind == .exam, let planned = s.plannedSeconds {
                let marks = [("half", planned / 2), ("last15", planned - 15 * spm)]
                for (name, mark) in marks where !s.cuesDone.contains(name) && elapsed >= mark {
                    s.cuesDone.append(name)
                    let meaningful = name == "half" || mark > planned / 2
                    if meaningful && elapsed - mark <= cueWindow { effects.append(.play(.cue)) }
                    effects.append(.save)
                }
            }
            if let planned = s.plannedSeconds, elapsed >= planned {
                state = s
                return effects + complete(&state, at: now.adding(-(elapsed - planned)), now: now)
            }
            let cap = flowCapMinutes * spm
            if s.kind == .flow, elapsed >= cap {
                state = s
                return effects + complete(&state, at: now.adding(-(elapsed - cap)), now: now)
            }
        }

        if s.phase == .breakTime, let start = s.breakStart, let length = s.breakSeconds {
            let over = start.seconds(to: now) - length
            if over >= 0 {
                s.phase = .ready
                s.readySince = start.adding(length)
                if over <= cueWindow { effects.append(.play(.breakEnd)) }
                effects += closeBreak(&s, clean: !s.breakDirty)
                effects.append(.save)
            }
        }

        if s.phase == .ready, let since = s.readySince, since.seconds(to: now) >= readyTimeout {
            state = nil
            return effects + [.cancel(SessionNotice.allCases), .keepAwake(false), .save]
        }

        state = s
        return effects
    }

    // MARK: - Away verdict

    /// Whether a lock signal belongs to this absence: the darwin lock arrives within 2 s of
    /// leaving; protected data goes away up to 13 s after it.
    static func accepts(_ source: LockSource, at: Instant, away: AwayRecord) -> Bool {
        switch source {
        case .darwin:
            return [away.inactiveAt, away.backgroundAt].contains { $0.map { $0.gap(at) <= darwinWindow } ?? false }
        case .protectedData:
            guard let background = away.backgroundAt, at.mono >= background.mono - 1 else { return false }
            return background.seconds(to: at) <= protectedWindow
        }
    }

    /// Decides what an absence meant, once he is back or on relaunch:
    /// 1. the block ended before he left: it completes at its end;
    /// 2. the screen was locked, or Relaxed mode: no penalty;
    /// 3. back within the grace time: a slip;
    /// 4. the block would have ended within the grace time: it completes at its end;
    /// 5. otherwise the block ends unfinished, counting focus up to the moment he left.
    /// On relaunch, a force-quit from the app switcher (inactive, never backgrounded) counts as leaving.
    static func judge(_ state: inout ActiveSession?, away: AwayRecord, now: Instant, relaunch: Bool) -> [Effect] {
        guard var s = state else { return [] }
        if s.phase == .breakTime || s.phase == .ready {
            if away.backgroundAt != nil && away.lockedAt == nil {
                s.breakDirty = true
                state = s
                return [.save]
            }
            return []
        }
        guard s.isFocusing else { return [] }
        guard let left = away.backgroundAt ?? (relaunch ? away.inactiveAt : nil) else { return [] }
        if let planned = s.plannedSeconds, focusElapsed(s, at: left) >= planned { return [] }
        if away.lockedAt != nil || !s.config.strictness.polices { return [] }

        // The allowed time away runs from leaving (or the last check-in); when studying in
        // another app, only from Focus Guard seeing a distracting app.
        let clock: Instant
        if s.config.studiesElsewhere {
            guard s.config.checksIn, let distracted = away.distractedAt,
                  away.checkedInAt.map({ $0.mono < distracted.mono }) ?? true else { return [] }
            clock = distracted
        } else {
            clock = away.checkedInAt ?? left
        }
        let allowance = s.config.graceSeconds
        let window = s.config.checksIn ? checkInWindow : 0
        if clock.seconds(to: now) <= allowance + window {
            if !s.config.studiesElsewhere { s.slips += 1 }
            state = s
            return [.save]
        }
        // Out of time; the block still completes if it would have ended first.
        let deadline = clock.adding(allowance + window)
        if let planned = s.plannedSeconds, focusElapsed(s, at: deadline) >= planned { return [] }
        state = nil
        return fail(s, reason: s.config.checksIn ? .noAnswer : .left,
                    countedUntil: s.config.checksIn ? clock.adding(allowance) : left,
                    awaySeconds: left.seconds(to: now))
    }

    /// "Still studying?" when the allowed time is up, and the notice that the block ended a
    /// minute later if there was no answer.
    static func checkInNotices(from clock: Instant, _ s: ActiveSession) -> [Effect] {
        let at = clock.wall.addingTimeInterval(s.config.graceSeconds)
        return [.schedule(.checkIn, at: at), .schedule(.awayEnd, at: at.addingTimeInterval(checkInWindow))]
    }

    // MARK: - Ending blocks

    static func complete(_ state: inout ActiveSession?, at end: Instant, now: Instant) -> [Effect] {
        guard var s = state else { return [] }
        let record = makeRecord(s, outcome: .completed, reason: .finished, end: end)
        var effects: [Effect] = [.record(record), .celebrate(record), .cancel(SessionNotice.block + SessionNotice.away)]
        if let length = breakLength(s, focusedMinutes: record.minutes) {
            s.phase = .breakTime
            s.breakStart = end
            s.breakSeconds = length
            s.breakDirty = false
            s.away = nil
            s.pausedAt = nil
            s.lockedSince = nil
            s.lastRecordID = record.id
            state = s
            effects.append(.schedule(.breakEnd, at: end.wall.addingTimeInterval(length)))
            effects.append(.save)
            effects += advance(&state, now: now)
        } else {
            state = nil
            effects += [.keepAwake(false), .save]
        }
        return effects
    }

    static func fail(_ s: ActiveSession, reason: EndReason, countedUntil: Instant, awaySeconds: Double?) -> [Effect] {
        let record = makeRecord(s, outcome: .unfinished, reason: reason, end: countedUntil)
        return [.record(record), .unfinished(record, awaySeconds: awaySeconds), .cancel(SessionNotice.allCases),
                .keepAwake(false), .play(.fizzle), .save]
    }

    static func interrupted(_ s: ActiveSession, until heartbeat: Instant) -> [Effect] {
        let record = makeRecord(s, outcome: .interrupted, reason: .interrupted, end: heartbeat)
        return [.record(record), .cancel(SessionNotice.allCases), .keepAwake(false), .save]
    }

    /// Break length in real seconds, or nil when the preset has no breaks.
    static func breakLength(_ s: ActiveSession, focusedMinutes: Double) -> Double? {
        let preset = s.config.preset
        let spm = s.config.secondsPerMinute
        switch s.kind {
        case .exam:
            return nil
        case .flow, .starter:
            return min(30, max(5, (focusedMinutes / 5).rounded())) * spm
        case .cycle:
            let long = preset.longEvery > 0 && s.round % preset.longEvery == 0
            let minutes = long ? preset.longBreakMinutes : preset.shortBreakMinutes
            return minutes > 0 ? Double(minutes) * spm : nil
        }
    }

    static func makeRecord(_ s: ActiveSession, outcome: Outcome, reason: EndReason, end: Instant) -> SessionRecord {
        let spm = s.config.secondsPerMinute
        return SessionRecord(
            id: s.id,
            day: Days(dayStartHour: s.config.dayStartHour).key(s.blockStart.wall),
            startedAt: s.blockStart.wall,
            endedAt: end.wall,
            presetID: s.config.preset.id,
            presetName: s.config.preset.name,
            strictness: s.config.strictness,
            subjectID: s.config.subjectID,
            intent: s.config.intent,
            round: s.round,
            plannedMinutes: s.plannedSeconds.map { $0 / spm },
            minutes: focusElapsed(s, at: end) / spm,
            lockedMinutes: lockedSeconds(s, at: end) / spm,
            slips: s.slips,
            outcome: outcome,
            reason: reason,
            parking: s.parking,
            topicID: s.config.topicID)
    }

    // MARK: - Helpers

    private static func resume(_ s: inout ActiveSession, at now: Instant) {
        if let p = s.pausedAt {
            let current = p.seconds(to: now)
            s.pausedSeconds += s.config.strictness == .relaxed ? current : min(current, pauseLimit)
        }
        s.pausedAt = nil
        s.phase = .focus
    }

    private static func closeBreak(_ s: inout ActiveSession, clean: Bool) -> [Effect] {
        guard let id = s.lastRecordID else { return [] }
        s.lastRecordID = nil
        return [.updateRecord(id, cleanBreak: clean)]
    }

    /// Notifications for the running block: its end (or Flowtime's cap, or the end of
    /// "Just 5 minutes") and the exam time checks.
    static func schedule(_ s: ActiveSession, now: Instant) -> [Effect] {
        guard s.phase == .focus else { return [] }
        let spm = s.config.secondsPerMinute
        let elapsed = focusElapsed(s, at: now)
        func at(_ mark: Double) -> Date { now.wall.addingTimeInterval(mark - elapsed) }
        var effects: [Effect] = []
        if let planned = s.plannedSeconds {
            effects.append(.schedule(s.kind == .starter ? .starter : .blockEnd, at: at(planned)))
            if s.kind == .exam {
                if elapsed < planned / 2 { effects.append(.schedule(.half, at: at(planned / 2))) }
                let last = planned - 15 * spm
                if last > planned / 2 && elapsed < last { effects.append(.schedule(.last15, at: at(last))) }
            }
        } else {
            effects.append(.schedule(.blockEnd, at: at(flowCapMinutes * spm)))
        }
        return effects
    }
}
