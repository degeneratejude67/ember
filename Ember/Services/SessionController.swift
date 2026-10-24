import SwiftUI
import UIKit

/// Owns the running session: feeds the engine events from the UI, the 1 Hz tick and the
/// lock detector, then carries out the effects it returns.
final class SessionController: ObservableObject {
    static let shared = SessionController()

    @Published private(set) var session: ActiveSession?
    /// The block that just completed; the celebration shows while this is set.
    @Published var celebration: CompletionSummary?
    /// The block that just ended early; the unfinished screen shows while this is set.
    @Published var unfinished: Unfinished?

    struct Unfinished: Equatable {
        var record: SessionRecord
        var awaySeconds: Double?
    }

    private let store: Store
    private let activeURL: URL
    private var ticker: Timer?
    private var lastHeartbeat = Instant.now()
    private var lastDarwinLock: Instant?

    init(store: Store = .shared) {
        self.store = store
        activeURL = AppEnv.dataRoot.appendingPathComponent("active.json")
        if AppEnv.isUITest, let screen = Fixtures.screen {
            Fixtures.apply(screen, to: self)
        } else if let raw = try? Data(contentsOf: activeURL),
                  let saved = try? JSONDecoder.ember.decode(ActiveSession.self, from: raw) {
            session = saved
            send(.relaunch)
        }
        LockDetector.shared.onEvent = { [weak self] event in self?.detector(event) }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    var prefs: Prefs { store.data.prefs }

    // MARK: - Commands

    func start(preset: Preset, strictness: Strictness, subjectID: UUID?, intent: String) {
        celebration = nil
        unfinished = nil
        let config = SessionConfig(
            preset: preset,
            strictness: strictness,
            subjectID: subjectID,
            intent: intent.trimmingCharacters(in: .whitespacesAndNewlines),
            graceSeconds: AppEnv.value(after: "-uitest-grace").flatMap(Double.init) ?? Double(prefs.graceSeconds),
            secondsPerMinute: AppEnv.secondsPerMinute,
            dayStartHour: prefs.dayStartHour)
        let (session, effects) = SessionEngine.start(config, now: .now())
        self.session = session
        run(effects)
        if UIAccessibility.isGuidedAccessEnabled { send(.guidedAccess(true)) }
        if !AppEnv.isUITest { Notifier.requestAuthorizationIfNeeded() }
        syncNoise()
    }

    /// Plays the chosen focus noise while a block runs, and silence otherwise.
    func syncNoise() {
        let wanted: NoiseColor? = session?.isFocusing == true ? prefs.noise : nil
        if Audio.shared.noise != wanted { Audio.shared.setNoise(wanted) }
    }

    /// Puts a prepared session in place without side effects (UI-test fixtures).
    func restore(_ session: ActiveSession) {
        self.session = session
    }

    func send(_ event: SessionEvent) {
        var state = session
        let effects = SessionEngine.reduce(&state, event, now: .now())
        if state != session { session = state }
        run(effects)
        syncNoise()
    }

    /// Sets the distraction tag on a block that ended early, then closes the screen.
    func closeUnfinished(tag: String?) {
        if let tag, let id = unfinished?.record.id,
           let i = store.data.sessions.firstIndex(where: { $0.id == id }) {
            store.data.sessions[i].distraction = tag
        }
        unfinished = nil
    }

    func setIntentResult(_ result: String, for id: UUID) {
        if let i = store.data.sessions.firstIndex(where: { $0.id == id }) {
            store.data.sessions[i].intentResult = result
        }
    }

    func setExamScore(_ score: String, for id: UUID) {
        let trimmed = score.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = store.data.sessions.firstIndex(where: { $0.id == id }) {
            store.data.sessions[i].examScore = trimmed.isEmpty ? nil : trimmed
        }
    }

    // MARK: - Clock and lifecycle

    private func tick() {
        guard session != nil else { return }
        send(.tick)
        let now = Instant.now()
        if var s = session, s.isFocusing, lastHeartbeat.seconds(to: now) >= 60 {
            lastHeartbeat = now
            s.heartbeat = now
            session = s
            saveActive()
        }
    }

    private func detector(_ event: DetectorEvent) {
        switch event {
        case .inactive:
            send(.inactive)
        case .background:
            send(.background)
            // A darwin lock can arrive before the app resigns active.
            if let lock = lastDarwinLock, lock.gap(.now()) <= SessionEngine.darwinWindow {
                send(.lock(.darwin, at: lock))
            }
            store.saveNow()
        case .active:
            send(.active)
        case let .darwinLock(at):
            lastDarwinLock = at
            send(.lock(.darwin, at: at))
        case let .protectedLost(at):
            send(.lock(.protectedData, at: at))
        case let .guidedAccess(on):
            send(.guidedAccess(on))
        }
    }

    // MARK: - Effects

    private func run(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .save:
                saveActive()
            case let .record(record):
                store.data.sessions.append(record)
                store.saveNow()
            case let .updateRecord(id, clean):
                if let i = store.data.sessions.firstIndex(where: { $0.id == id }) {
                    store.data.sessions[i].cleanBreak = clean
                }
            case let .celebrate(record):
                celebration = CompletionSummary.make(record: record, data: store.data)
            case let .unfinished(record, away):
                celebration = nil
                unfinished = Unfinished(record: record, awaySeconds: away)
            case let .play(sound):
                if prefs.soundsOn { Audio.shared.play(sound) }
            case let .schedule(notice, date):
                Notifier.schedule(notice, at: date, content: content(for: notice))
            case let .cancel(notices):
                Notifier.cancel(notices)
            case let .keepAwake(on):
                UIApplication.shared.isIdleTimerDisabled = on
            }
        }
    }

    private func saveActive() {
        if let session, let raw = try? JSONEncoder.ember.encode(session) {
            try? raw.write(to: activeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else {
            try? FileManager.default.removeItem(at: activeURL)
        }
    }

    private func content(for notice: SessionNotice) -> Notifier.Content {
        let subject = store.data.subject(session?.config.subjectID)?.name
        switch notice {
        case .blockEnd:
            if session?.kind == .flow {
                return .init(title: "Three hours of Flowtime", body: "That's the limit for one block. Take a real break.", sound: .complete)
            }
            let what = subject.map { " of \($0)" } ?? ""
            let minutes = Int((session?.plannedSeconds ?? 0) / (session?.config.secondsPerMinute ?? 60))
            let next = session?.config.preset.hasBreaks == true ? " Time for a break." : ""
            return .init(title: "Block complete!", body: "\(minutes) minutes\(what) done.\(next)", sound: .complete)
        case .breakEnd:
            let round = (session?.round ?? 0) + 1
            return .init(title: "Break's over", body: "Round \(round) is ready when you are.", sound: .breakEnd)
        case .nudge:
            let grace = Int(session?.config.graceSeconds ?? 10)
            return .init(title: "Come back to Ember", body: "Your block ends if you stay away more than \(grace) seconds.", sound: .nudge)
        case .half:
            return .init(title: "Halfway", body: "Half the exam time is gone.", sound: .cue)
        case .last15:
            return .init(title: "15 minutes left", body: "Start wrapping up your answers.", sound: .cue)
        case .starter:
            return .init(title: "5 minutes done", body: "Nice start. It carries on as Flowtime; finish whenever you like.", sound: .cue)
        case .pauseOver:
            return .init(title: "Pause over", body: "Your block is running again.", sound: .cue)
        }
    }
}
