import AppKit
import CoachCore
import SwiftUI
import UserNotifications

/// Revision reminders.
///
/// - Morning: "N files to revise today", scheduled for the next 4 weeks with each day's list (due files
///   plus "getting ahead" files up to the daily goal, so there's a reminder every day).
/// - Evening catch-up (optional): only fires while today's list isn't done; since Coach reschedules
///   after every review, finishing it cancels the reminder.
/// - Clicking a reminder (or "Start Review") opens the revision page for the most urgent due file;
///   "Remind Me in 1 Hour" snoozes.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    static let enabledKey = "reminderEnabled"
    static let minutesKey = "reminderMinutes"              // minutes after midnight; default 9:00
    static let eveningEnabledKey = "eveningReminderEnabled"
    static let eveningMinutesKey = "eveningReminderMinutes" // default 19:00

    private static let category = "coach.due"
    private static let startAction = "coach.start"
    private static let snoozeAction = "coach.snooze"
    private static let snoozeID = "coach.snooze"
    /// Days scheduled ahead. macOS keeps at most 64 pending notifications per app: 2 × 28 + snooze + tests fits.
    static let daysAhead = 28
    private static let morningIDs = (0..<daysAhead).map { "coach.daily.\($0)" }
    private static let eveningIDs = (0..<daysAhead).map { "coach.evening.\($0)" }

    /// Notifications only work from inside a real .app bundle (not `swift run`).
    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
    var minutes: Int { UserDefaults.standard.object(forKey: Self.minutesKey) as? Int ?? 9 * 60 }
    var eveningEnabled: Bool { UserDefaults.standard.object(forKey: Self.eveningEnabledKey) as? Bool ?? false }
    var eveningMinutes: Int { UserDefaults.standard.object(forKey: Self.eveningMinutesKey) as? Int ?? 19 * 60 }

    private weak var store: VaultStore?
    private var openWindow: OpenWindowAction?
    /// A reminder was clicked before the app's windows were ready (e.g. Coach was launched by the click).
    private var pendingOpen = false

    // MARK: Setup

    /// Call at launch, before any notification can be delivered to us.
    func setUp() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: Self.startAction, title: "Start Review", options: [.foreground])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Remind Me in 1 Hour", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [start, snooze], intentIdentifiers: [], options: []),
        ])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Gives the notifier a way to open windows. Called from the app's scenes once they exist.
    func attach(store: VaultStore, openWindow: OpenWindowAction) {
        self.store = store
        self.openWindow = openWindow
        if pendingOpen {
            pendingOpen = false
            // Give the vault a moment to load after a cold launch.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                self.startRevising()
            }
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        guard isAvailable else { return .notDetermined }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Scheduling

    func reschedule(topics: [Topic]) {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.morningIDs + Self.eveningIDs)

        let cal = Calendar.current
        let now = Date()
        func schedule(ids: [String], minutes: Int, evening: Bool) {
            var fire = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now)!
            if fire <= now { fire = cal.date(byAdding: .day, value: 1, to: fire)! }
            for (i, id) in ids.enumerated() {
                let day = cal.date(byAdding: .day, value: i, to: fire)!
                let plan = Self.plan(topics, on: day)
                guard !plan.today.isEmpty else { continue }
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: day)
                center.add(UNNotificationRequest(identifier: id, content: Self.content(plan, style: evening ? .evening : .morning),
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        }
        if enabled { schedule(ids: Self.morningIDs, minutes: minutes, evening: false) }
        if eveningEnabled { schedule(ids: Self.eveningIDs, minutes: eveningMinutes, evening: true) }
    }

    /// "Remind Me in 1 Hour".
    func snooze(topics: [Topic]) {
        let plan = Self.plan(topics, on: Date())
        guard isAvailable, !plan.today.isEmpty else { return }
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: Self.snoozeID, content: Self.content(plan, style: .snoozed),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)))
    }

    /// Sends the reminder you'd get now, in a couple of seconds, so you can check it works.
    func sendTest(topics: [Topic], after seconds: TimeInterval = 2) {
        guard isAvailable else { return }
        let plan = Self.plan(topics, on: Date())
        let content: UNMutableNotificationContent
        if plan.today.isEmpty {
            content = UNMutableNotificationContent()
            content.title = "Nothing to revise right now"
            content.body = "You're caught up. This is how Coach's reminders will look."
            content.sound = .default
        } else {
            content = Self.content(plan, style: .morning)
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "coach.test.\(UUID().uuidString)", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
    }

    /// `open -a Coach --args --test-notification`: schedules a test reminder 15 s ahead, then quits,
    /// so you can see that reminders arrive while Coach is closed.
    func runLaunchTestIfRequested() {
        guard CommandLine.arguments.contains("--test-notification") else { return }
        Task { @MainActor in
            let status = await authorizationStatus()
            print("Coach notification permission: \(status.rawValue) (2 = allowed, 1 = denied, 0 = not asked yet)")
            try? await Task.sleep(for: .seconds(3)) // let the vault load so the reminder lists real files
            sendTest(topics: store?.topics ?? [], after: 15)
            print("Test reminder scheduled for 15 s from now; quitting Coach.")
            try? await Task.sleep(for: .seconds(1))
            NSApp.terminate(nil)
        }
    }

    // MARK: Content

    private enum Style { case morning, evening, snoozed }

    private static func plan(_ topics: [Topic], on day: Date) -> DailyPlan {
        DailyPlan(topics: topics, goal: VaultStore.savedDailyGoal, now: day)
    }

    private static func content(_ plan: DailyPlan, style: Style) -> UNMutableNotificationContent {
        let list = plan.today
        let n = list.count
        let files = n == 1 ? "1 file" : "\(n) files"
        let content = UNMutableNotificationContent()
        switch style {
        case .morning: content.title = "\(files) to revise today"
        case .evening: content.title = "Still \(files) to go today"
        case .snoozed: content.title = "Reminder: \(files) to revise"
        }

        let critical = list.filter { $0.confidence <= 2 }.count
        content.subtitle = [
            plan.due.isEmpty ? nil : "\(plan.due.count) due",
            plan.ahead.isEmpty ? nil : "\(plan.ahead.count) to get ahead",
            critical > 0 ? "\(critical) critical" : nil,
            plan.moreDue.isEmpty ? nil : "+\(plan.moreDue.count) more due",
        ].compactMap { $0 }.joined(separator: " · ")

        let names = list.prefix(3).map(\.title).joined(separator: ", ")
        var body = n > 3 ? "\(names) and \(n - 3) more" : names
        if style == .evening { body += ". A few minutes now keeps the habit going." }
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = "coach.due"
        return content
    }

    // MARK: Responses

    /// Opens the revision page for the first file on today's list.
    func startRevising() {
        guard let store, let openWindow else {
            pendingOpen = true
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let first = store.reviewQueue.first {
            openWindow.revise(first.id)
        } else {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func handle(action: String) {
        switch action {
        case UNNotificationDefaultActionIdentifier, Self.startAction: startRevising()
        case Self.snoozeAction: snooze(topics: store?.topics ?? [])
        default: break
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        await MainActor.run { self.handle(action: action) }
    }

    /// Show reminders even while Coach is the frontmost app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
