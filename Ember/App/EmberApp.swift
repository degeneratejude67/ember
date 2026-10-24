import SwiftUI
import UserNotifications

@main
struct EmberApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.ember)
                .onChange(of: scenePhase) { _, phase in LockDetector.shared.scene(phase) }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Notifier.registerCategories()
        LockDetector.shared.start()
        Audio.shared.preload()
        _ = SessionController.shared
        return true
    }

    /// "I'm still studying" from the check-in, answered without opening Ember.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == Notifier.checkInOK else { return }
        await MainActor.run { SessionController.shared.checkIn() }
    }

    /// While Ember is on screen it plays its own sounds, so notifications stay silent.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }
}
