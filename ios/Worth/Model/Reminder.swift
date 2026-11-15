import UserNotifications

/// The monthly check-in reminder: a local notification on the 1st of every month at 9:00 (nothing leaves the phone).
enum Reminder {
    private static let id = "monthly-checkin"

    /// Asks for permission (the first time) and schedules it. False when notifications aren't allowed.
    static func enable() async -> Bool {
        let c = UNUserNotificationCenter.current()
        guard (try? await c.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return false }
        let n = UNMutableNotificationContent()
        n.title = "Time for your check-in"
        n.body = "A new month has started. Update what changed and see how your net worth moved."
        n.sound = .default
        var when = DateComponents(); when.day = 1; when.hour = 9
        do { try await c.add(UNNotificationRequest(identifier: id, content: n, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))) }
        catch { return false }
        return true
    }

    static func disable() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]) }
}
