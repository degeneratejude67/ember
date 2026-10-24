import SwiftUI
import UIKit
import UserNotifications

/// Watches everything that can tell "locked the screen" apart from "left the app": the app
/// lifecycle, SpringBoard's darwin notifications, protected-data availability, screen
/// brightness and Guided Access. For now it records what it sees in the Lock Lab log, judges
/// each absence the way Deep Focus will, and tries the leave nudge.
final class LockDetector: ObservableObject {
    static let shared = LockDetector()

    static let darwinNames = [
        "com.apple.springboard.lockcomplete",
        "com.apple.springboard.lockstate",
        "com.apple.springboard.hasBlankedScreen",
    ]
    /// A darwin lock this close to leaving (either side) means the screen was locked.
    static let directLockWindow = 2.0
    static let nudgeDelay = 3.0
    static let graceSeconds = 10.0

    /// Arms the leave-nudge test: a notification 3 s after leaving, cancelled by a lock.
    @Published var nudgeArmed = false
    @Published private(set) var lastVerdict = "No absence yet."
    @Published private(set) var guidedAccess = UIAccessibility.isGuidedAccessEnabled

    private let log = LabLog.shared
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var away = Away()
    private var lastDarwinLock: Instant?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var poll: Timer?
    private var lastProtected = true

    /// One absence from the screen, from resigning active to becoming active again.
    private struct Away {
        var inactiveAt: Instant?
        var backgroundAt: Instant?
        var darwinLockAt: Instant?
        var protectedLostAt: Instant?

        var leftAt: Instant? { inactiveAt ?? backgroundAt }
    }

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        func on(_ name: Notification.Name, _ handler: @escaping (LockDetector) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                if let self { handler(self) }
            })
        }
        on(UIApplication.willResignActiveNotification) { $0.resignedActive() }
        on(UIApplication.didEnterBackgroundNotification) { $0.enteredBackground() }
        on(UIApplication.willEnterForegroundNotification) { $0.log.add("app.willEnterForeground", $0.offsetText()) }
        on(UIApplication.didBecomeActiveNotification) { $0.becameActive() }
        on(UIApplication.protectedDataWillBecomeUnavailableNotification) { $0.protectedLost("notification") }
        on(UIApplication.protectedDataDidBecomeAvailableNotification) { $0.log.add("protected.didBecomeAvailable", $0.offsetText()) }
        on(UIApplication.willTerminateNotification) { $0.log.add("app.willTerminate") }
        on(UIScreen.brightnessDidChangeNotification) { $0.log.add("screen.brightness", $0.brightnessText) }
        on(UIAccessibility.guidedAccessStatusDidChangeNotification) { detector in
            let enabled = UIAccessibility.isGuidedAccessEnabled
            detector.guidedAccess = enabled
            detector.log.add("guidedAccess", enabled ? "on" : "off")
        }

        let darwin = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.darwinNames {
            CFNotificationCenterAddObserver(darwin, observer, { _, observer, name, _, _ in
                guard let observer, let name else { return }
                let detector = Unmanaged<LockDetector>.fromOpaque(observer).takeUnretainedValue()
                let value = name.rawValue as String
                DispatchQueue.main.async { detector.receivedDarwin(value) }
            }, name as CFString, nil, .deliverImmediately)
        }

        log.add("lab.start", "guidedAccess=\(UIAccessibility.isGuidedAccessEnabled ? "on" : "off") " +
                "protected=\(UIApplication.shared.isProtectedDataAvailable) \(brightnessText)")
    }

    /// SwiftUI's scene phase, logged next to the UIKit notifications.
    func scene(_ phase: ScenePhase) {
        log.add("scene.\(phase)", offsetText())
    }

    func requestNotifications() {
        guard !AppEnv.isUITest else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            LabLog.shared.add("notifications", granted ? "allowed" : "denied")
        }
    }

    // MARK: - Lifecycle

    private func resignedActive() {
        away = Away(inactiveAt: .now())
        log.add("app.willResignActive", brightnessText)
    }

    private func enteredBackground() {
        let now = Instant.now()
        if away.inactiveAt == nil { away.inactiveAt = now }
        away.backgroundAt = now
        log.add("app.didEnterBackground", "\(offsetText()) \(brightnessText) protected=\(UIApplication.shared.isProtectedDataAvailable)")
        if let lock = lastDarwinLock, lock.gap(now) <= Self.directLockWindow {
            away.darwinLockAt = lock
        }
        beginBackgroundWatch()
        if nudgeArmed && away.darwinLockAt == nil { scheduleNudge() }
    }

    private func becameActive() {
        endBackgroundWatch()
        log.add("app.didBecomeActive", "\(offsetText()) \(brightnessText)")
        defer { away = Away() }
        guard let left = away.leftAt else { return }
        let total = left.seconds(to: .now())
        let verdict: String
        if away.backgroundAt == nil {
            verdict = String(format: "Inactive only, %.1f s (Control Center, Notification Center or the app switcher): not leaving.", total)
        } else if let lock = away.darwinLockAt, lock.gap(left) <= Self.directLockWindow {
            verdict = String(format: "LOCKED: darwin lockcomplete at %+.1f s. Away %.1f s.", lock.mono - left.mono, total)
        } else if let lost = away.protectedLostAt, let background = away.backgroundAt {
            verdict = String(format: "LOCKED: protected data lost %.1f s after leaving. Away %.1f s.", background.seconds(to: lost), total)
        } else if total <= Self.graceSeconds {
            verdict = String(format: "LEFT for %.1f s: a slip (within the %.0f s grace).", total, Self.graceSeconds)
        } else {
            verdict = String(format: "LEFT for %.1f s: a real block would end unfinished.", total)
        }
        lastVerdict = verdict
        log.add("verdict", verdict)
        cancelNudge(reason: nil)
    }

    private func receivedDarwin(_ name: String) {
        let short = name.replacingOccurrences(of: "com.apple.springboard.", with: "")
        let now = Instant.now()
        log.add("darwin.\(short)", offsetText())
        guard short == "lockcomplete" else { return }
        lastDarwinLock = now
        if let left = away.leftAt, away.darwinLockAt == nil, left.gap(now) <= Self.directLockWindow {
            away.darwinLockAt = now
            cancelNudge(reason: "darwin lock")
        }
    }

    private func protectedLost(_ source: String) {
        if away.leftAt != nil, away.protectedLostAt == nil { away.protectedLostAt = .now() }
        log.add("protected.lost", "\(source) \(offsetText())")
    }

    // MARK: - Background watch

    /// Keeps the app running for up to 30 s after leaving (a background task) and polls
    /// protected-data availability twice a second.
    private func beginBackgroundWatch() {
        endBackgroundWatch()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "LockLab") { [weak self] in
            guard let self else { return }
            self.log.add("backgroundTask.expired", self.offsetText())
            self.endBackgroundWatch()
        }
        lastProtected = UIApplication.shared.isProtectedDataAvailable
        var ticks = 0
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            ticks += 1
            let available = UIApplication.shared.isProtectedDataAvailable
            if available != self.lastProtected {
                self.lastProtected = available
                if available {
                    self.log.add("poll.protected", "available \(self.offsetText())")
                } else {
                    self.protectedLost("poll")
                }
            }
            if ticks % 10 == 0 {
                self.log.add("background.tick", "\(self.offsetText()) protected=\(available) \(self.brightnessText)")
            }
            if ticks >= 60 { self.endBackgroundWatch() }
        }
    }

    private func endBackgroundWatch() {
        poll?.invalidate()
        poll = nil
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    // MARK: - Leave nudge

    private func scheduleNudge() {
        let content = UNMutableNotificationContent()
        content.title = "Come back to Ember"
        content.body = "Lock Lab: you left the app. A real block would end in 10 seconds."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("nudge.wav"))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.nudgeDelay, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lab.nudge", content: content, trigger: trigger))
        log.add("nudge.scheduled", String(format: "+%.0f s", Self.nudgeDelay))
    }

    private func cancelNudge(reason: String?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["lab.nudge"])
        center.removeDeliveredNotifications(withIdentifiers: ["lab.nudge"])
        if let reason { log.add("nudge.cancelled", reason) }
    }

    // MARK: - Text

    private var brightnessText: String {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
        return String(format: "brightness=%.2f", screen?.brightness ?? -1)
    }

    /// Time since leaving, while away.
    private func offsetText() -> String {
        guard let left = away.leftAt else { return "" }
        return String(format: "+%.2f s", left.seconds(to: .now()))
    }
}
