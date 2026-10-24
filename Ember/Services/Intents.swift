import AppIntents
import Foundation
import UserNotifications

// App detection. iPadOS doesn't tell Ember which app is open, so Shortcuts automations do:
// "When CollaNote is opened" runs "Ember: in my study app", "When Safari is opened" runs
// "Ember: in a helper app", "When CollaNote is closed" runs "Ember: in another app".
// App Intents need no special entitlement, so this works with a free Apple ID.

struct StudyAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Ember: in my study app"
    static var description = IntentDescription(
        "Tell Ember you opened your study app (CollaNote, Slate, Files). Time there counts as focus, with no limit.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await AwayLog.report(.study)
        return .result()
    }
}

struct HelperAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Ember: in a helper app"
    static var description = IntentDescription(
        "Tell Ember you opened a helper app (Safari, YouTube, Gemini, Claude). The block keeps running; Ember checks in after the helper-app time (10 minutes).")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await AwayLog.report(.helper)
        return .result()
    }
}

struct OtherAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Ember: in another app"
    static var description = IntentDescription(
        "Tell Ember you left your study app or opened any other app. Ember checks in after the other-app time (3 minutes).")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await AwayLog.report(.other)
        return .result()
    }
}

/// The original Focus Guard question. With strict time away (10 s) a "yes" sends him straight
/// back to Ember; otherwise it counts as "in another app".
struct IsFocusingIntent: AppIntent {
    static var title: LocalizedStringResource = "Is Ember focusing?"
    static var description = IntentDescription(
        "True while a strict Ember block (10 seconds away) is running. Use it in an automation to bounce back to Ember.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        guard let session = AwayLog.activeSession(), session.isFocusing else { return .result(value: false) }
        guard session.config.checksIn else { return .result(value: true) }
        await AwayLog.report(.other)
        return .result(value: false)
    }
}

struct EmberShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StudyAppIntent(), phrases: ["\(.applicationName): in my study app"],
                    shortTitle: "In my study app", systemImageName: "pencil.and.scribble")
        AppShortcut(intent: HelperAppIntent(), phrases: ["\(.applicationName): in a helper app"],
                    shortTitle: "In a helper app", systemImageName: "globe")
        AppShortcut(intent: OtherAppIntent(), phrases: ["\(.applicationName): in another app"],
                    shortTitle: "In another app", systemImageName: "square.grid.2x2")
    }
}

/// Where the automations said he went while Ember was away, kept in a small file until Ember
/// comes back (it may be asleep or not running when they fire). The intent also schedules
/// the check-in notification itself, since Ember can't while it's asleep.
enum AwayLog {
    struct Event: Codable, Equatable {
        var at: Date
        var place: AwayPlace
    }

    private static var url: URL { AppEnv.dataRoot.appendingPathComponent("away-events.json") }

    static func activeSession() -> ActiveSession? {
        let file = AppEnv.dataRoot.appendingPathComponent("active.json")
        guard let raw = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder.ember.decode(ActiveSession.self, from: raw)
    }

    static func isFocusing() -> Bool { activeSession()?.isFocusing == true }

    static func report(_ place: AwayPlace, now: Date = Date()) async {
        guard let session = activeSession(), session.isFocusing else { return }
        var events = load()
        let last = events.last?.place ?? session.away?.currentPlace
        // the same place again keeps its clock running
        guard last != place else { return }
        // "CollaNote closed" right after "Safari opened" is the same switch seen twice
        if place == .other, let previous = events.last, now.timeIntervalSince(previous.at) < 3 { return }
        events.append(Event(at: now, place: place))
        save(Array(events.suffix(100)))
        guard session.config.strictness.polices, session.away?.lockedAt == nil else { return }
        if let allowance = session.config.allowance(place), session.config.checksIn {
            let at = now.addingTimeInterval(allowance)
            Notifier.schedule(.checkIn, at: at, content: Notifier.checkInContent(minutes: Int(allowance / 60)))
            Notifier.schedule(.awayEnd, at: at.addingTimeInterval(SessionEngine.checkInWindow), content: Notifier.awayEndContent)
        } else {
            Notifier.cancel([.checkIn, .awayEnd])
        }
    }

    /// Events since the last call, oldest first; the file is emptied.
    static func take() -> [Event] {
        let events = load()
        try? FileManager.default.removeItem(at: url)
        return events
    }

    private static func load() -> [Event] {
        guard let raw = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder.ember.decode([Event].self, from: raw)) ?? []
    }

    private static func save(_ events: [Event]) {
        guard let raw = try? JSONEncoder.ember.encode(events) else { return }
        try? raw.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
