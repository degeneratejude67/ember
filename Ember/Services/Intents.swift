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
        .result(value: FocusGuard.isFocusing())
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
    /// Reads the saved session without starting the session controller, so a background
    /// launch for the intent never judges an absence.
    static func isFocusing() -> Bool {
        let url = AppEnv.dataRoot.appendingPathComponent("active.json")
        guard let raw = try? Data(contentsOf: url),
              let session = try? JSONDecoder.ember.decode(ActiveSession.self, from: raw) else { return false }
        return session.isFocusing
    }
}
