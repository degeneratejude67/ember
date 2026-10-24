import AppIntents
import Foundation

/// Focus Guard: a Shortcuts automation on YouTube, Instagram or games asks this, and opens
/// Ember when it is true, so a block bounces him straight back. App Intents need no special
/// entitlement, so this works with a free Apple ID.
struct IsFocusingIntent: AppIntent {
    static var title: LocalizedStringResource = "Is Ember focusing?"
    static var description = IntentDescription(
        "True while an Ember focus block is running. Use it in an automation to bounce back to Ember from distracting apps.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let focusing = FocusGuard.isFocusing()
        // The automation only asks when a distracting app opens, so a "yes" is a bounce.
        if focusing { FocusGuard.recordBounce() }
        return .result(value: focusing)
    }
}

struct EmberShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: IsFocusingIntent(),
                    phrases: ["Is \(.applicationName) focusing?"],
                    shortTitle: "Is Ember focusing?",
                    systemImageName: "flame.fill")
    }
}

enum FocusGuard {
    private static var bouncesURL: URL { AppEnv.dataRoot.appendingPathComponent("guard-bounces.json") }

    /// Notes that Focus Guard sent him back; the session turns it into a slip on return.
    static func recordBounce() {
        var bounces = (try? JSONDecoder.ember.decode([Date].self, from: Data(contentsOf: bouncesURL))) ?? []
        bounces.append(Date())
        if let raw = try? JSONEncoder.ember.encode(Array(bounces.suffix(50))) {
            try? raw.write(to: bouncesURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Bounces since the last call, oldest first.
    static func takeBounces() -> [Date] {
        guard let raw = try? Data(contentsOf: bouncesURL) else { return [] }
        try? FileManager.default.removeItem(at: bouncesURL)
        return (try? JSONDecoder.ember.decode([Date].self, from: raw)) ?? []
    }

    /// Reads the saved session without starting the session controller, so a background
    /// launch for the intent never judges an absence.
    static func isFocusing() -> Bool {
        let url = AppEnv.dataRoot.appendingPathComponent("active.json")
        guard let raw = try? Data(contentsOf: url),
              let session = try? JSONDecoder.ember.decode(ActiveSession.self, from: raw) else { return false }
        return session.isFocusing
    }
}
