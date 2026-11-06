import CoachCore
import Foundation
import UserNotifications

/// Daily "N topics due" reminder. Schedules the next 7 days, each with that day's real count.
@MainActor
final class Notifier {
    static let shared = Notifier()

    static let enabledKey = "reminderEnabled"
    static let minutesKey = "reminderMinutes" // minutes after midnight; default 9:00

    /// Notifications only work from inside a real .app bundle (not `swift run`).
    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
    var minutes: Int { UserDefaults.standard.object(forKey: Self.minutesKey) as? Int ?? 9 * 60 }

    func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func reschedule(topics: [Topic]) {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let ids = (0..<7).map { "coach.daily.\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled else { return }

        let cal = Calendar.current
        let now = Date()
        var fire = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now)!
        if fire <= now { fire = cal.date(byAdding: .day, value: 1, to: fire)! }

        for (i, id) in ids.enumerated() {
            let day = cal.date(byAdding: .day, value: i, to: fire)!
            let due = topics.filter { $0.isDue(now: day) }.sorted(by: Topic.urgency)
            guard !due.isEmpty else { continue }

            let content = UNMutableNotificationContent()
            content.title = due.count == 1 ? "1 topic to revise today" : "\(due.count) topics to revise today"
            let names = due.prefix(3).map(\.title).joined(separator: ", ")
            content.body = due.count > 3 ? "\(names) and \(due.count - 3) more" : names
            content.sound = .default

            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: day)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
