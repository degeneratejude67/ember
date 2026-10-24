import Foundation
import UserNotifications

/// Local notifications. Session notifications are scheduled and cancelled directly by the
/// session; their identifiers are the `SessionNotice` raw values.
enum Notifier {
    struct Content {
        var title: String
        var body: String
        var sound: SoundEffect
    }

    static let checkInCategory = "checkin"
    static let checkInOK = "checkin.ok"
    static let checkInBack = "checkin.back"

    static func checkInContent(minutes: Int) -> Content {
        Content(title: "Still studying?",
                body: "You've been away from Ember for \(minutes) minutes. Tap \u{201C}I'm still studying\u{201D} or come back, or the block ends in a minute.",
                sound: .nudge)
    }

    static let awayEndContent = Content(title: "Block ended",
                                        body: "No answer to the check-in, so the block ended. The minutes before still count.",
                                        sound: .fizzle)

    /// The check-in's two buttons: answer from the notification, or jump back into Ember.
    static func registerCategories() {
        let ok = UNNotificationAction(identifier: checkInOK, title: "I'm still studying", options: [])
        let back = UNNotificationAction(identifier: checkInBack, title: "Back to Ember", options: [.foreground])
        let category = UNNotificationCategory(identifier: checkInCategory, actions: [ok, back], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    static func schedule(_ notice: SessionNotice, at date: Date, content: Content) {
        guard !AppEnv.isUITest else { return }
        let body = UNMutableNotificationContent()
        body.title = content.title
        body.body = content.body
        body.sound = UNNotificationSound(named: UNNotificationSoundName(content.sound.fileName))
        if notice == .checkIn { body.categoryIdentifier = checkInCategory }
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notice.rawValue, content: body, trigger: trigger))
    }

    /// Replaces the planner's reminders ("r." identifiers) with `plan`.
    static func apply(_ plan: [PlannedNotice]) {
        guard !AppEnv.isUITest else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let wanted = Set(plan.map(\.id))
            let stale = pending.map(\.identifier).filter { $0.hasPrefix("r.") && !wanted.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for notice in plan {
                let content = UNMutableNotificationContent()
                content.title = notice.title
                content.body = notice.body
                content.sound = UNNotificationSound(named: UNNotificationSoundName(SoundEffect.nudge.fileName))
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notice.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger))
            }
        }
    }

    static func cancel(_ notices: [SessionNotice]) {
        let ids = notices.map(\.rawValue)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
