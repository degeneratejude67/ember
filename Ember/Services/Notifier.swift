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
