import Foundation
import UserNotifications

// Reminders: two quiet notifications a day, both optional.
//   Morning: new daily quests are up.
//   Evening: only if today's dailies aren't finished (and a streak is at stake).

enum Reminders {
    private static let morningId = "spade.morning"
    private static let eveningId = "spade.evening"

    /// Asks the player for permission to send notifications. Returns whether they said yes.
    static func askPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Brings the scheduled reminders in line with the save. Call after anything changes.
    static func refresh(for save: Save) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningId, eveningId])
        guard save.settings.reminders, save.onboarded else { return }

        // Every morning at 9.
        let morning = UNMutableNotificationContent()
        morning.title = "New quests are up"
        morning.body = "Three fresh quests are waiting at the dig."
        morning.sound = .default
        var nine = DateComponents()
        nine.hour = 9
        nine.minute = 0
        center.add(UNNotificationRequest(identifier: morningId, content: morning, trigger: UNCalendarNotificationTrigger(dateMatching: nine, repeats: true)))

        // This evening at 7:30, but only if there is still something to do today.
        let left = save.boards.daily.quests.filter { !$0.done }.count
        guard left > 0 else { return }
        let clock = GameClock.device
        var today = clock.components(Date())
        today.hour = 19
        today.minute = 30
        guard let when = clock.date(from: today), when > Date() else { return }
        let evening = UNMutableNotificationContent()
        evening.title = save.streak.count > 1 ? "Keep your \(save.streak.count)-day streak" : "The lantern is still low"
        evening.body = left == 1 ? "One quest left today." : "\(left) quests left today."
        evening.sound = .default
        center.add(UNNotificationRequest(identifier: eveningId, content: evening, trigger: UNCalendarNotificationTrigger(dateMatching: today, repeats: false)))
    }
}
