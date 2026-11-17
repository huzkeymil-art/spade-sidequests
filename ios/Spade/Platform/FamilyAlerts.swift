import BackgroundTasks
import UIKit
import UserNotifications

// Family notifications.
//
//   A child's phone:  "New quest from Sam"        when a parent adds a quest
//   A parent's phone: "Tess finished a quest"     when a child finishes one
//
// There is no server of ours to send these. The phones already keep in step
// through iCloud, and iCloud wakes Spade in the background when the other
// phone changes something (a silent push). Spade then syncs, sees what is
// new (familyNews in Core/Family.swift), and shows a notification from the
// phone itself. A background refresh now and then catches anything a silent
// push missed.
//
// iOS decides when Spade may wake up. It won't, for example, if Spade was
// swiped away in the app switcher, or in Low Power Mode. Then the news shows
// the next time Spade is opened.

@MainActor
enum FamilyAlerts {
    private static let key = "familyAlerts"

    /// The switch in Settings. On unless the player turned it off.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    struct Alert: Equatable {
        var title: String
        var body: String
        /// The short line for the in-app notice, when Spade is open.
        var note: String
        /// Notifications about the same child (or family) are grouped together.
        var thread: String
        /// The tab to open when the notification is tapped.
        var tab: AppTab
    }

    /// Shows notifications now.
    static func post(_ alerts: [Alert]) async {
        guard enabled, !alerts.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.threadIdentifier = alert.thread
            content.userInfo = [tabKey: alert.tab.rawValue]
            let request = UNNotificationRequest(identifier: "spade.family.\(UUID().uuidString)", content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    /// Read by the notification delegate too, which isn't tied to the main thread.
    nonisolated static let tabKey = "spade.tab"

    /// Whether the player said no to notifications in the past. Only the Settings app can change that.
    static func blocked() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    private static var asking = false

    /// Asks the player, once, whether Spade may show notifications. Only for families, only
    /// while Spade is on screen, and only when no sheet is open, so the question comes at a
    /// calm moment: after the invite was sent, or after "You're in" was closed.
    static func askIfCalm() {
        guard enabled, !asking, UIApplication.shared.applicationState == .active, !Share.isShowingSomething else { return }
        asking = true
        Task {
            defer { asking = false }
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            guard status == .notDetermined, !Share.isShowingSomething else { return }
            _ = await Reminders.askPermission()
        }
    }
}

/// Where iOS hands over notifications: taps on them, and ones that arrive while Spade is open.
final class NotificationDoor: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDoor()

    /// While Spade is open it shows its own notices instead, so nothing is shown twice.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    /// A family notification was tapped: open the tab it is about.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let tab = response.notification.request.content.userInfo[FamilyAlerts.tabKey] as? String
        Task { @MainActor in
            if let tab, let which = AppTab(rawValue: tab) { CloudDoor.open(which) }
            completionHandler()
        }
    }
}

/// A check for family news every so often, in the background. iOS decides when (often every
/// hour or few), so it is a safety net for when iCloud's nudge doesn't wake Spade.
enum FamilyCheck {
    static let id = "com.huzkeymil.spade.family"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run() async {
        schedule()
        await GameStore.shared.syncFamilyAndWait()
    }
}
