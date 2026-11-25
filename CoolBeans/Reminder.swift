import UserNotifications

// Daily 2 PM nudge to stop caffeine for better sleep.
enum Reminder {
    static func set(_ on: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["cutoff"])
        guard on else { return }
        center.requestAuthorization(options: [.alert]) { ok, _ in
            guard ok else { return }
            let content = UNMutableNotificationContent()
            content.title = "Caffeine cutoff"
            content.body = "Skip coffee from now on for better sleep."
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 14), repeats: true)
            center.add(UNNotificationRequest(identifier: "cutoff", content: content, trigger: trigger))
        }
    }
}
