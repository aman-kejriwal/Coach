import AppKit
import CoachCore
import SwiftUI
import UserNotifications

enum VaultPicker {
    /// Lets the user choose a folder. Returns nil on cancel. Warns if it doesn't look like an Obsidian vault.
    @MainActor
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Vault"
        panel.message = "Choose your Obsidian vault folder"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        if !FileManager.default.fileExists(atPath: url.appendingPathComponent(".obsidian").path) {
            let alert = NSAlert()
            alert.messageText = "This folder isn't an Obsidian vault yet"
            alert.informativeText = "There's no .obsidian folder in “\(url.lastPathComponent)”. Coach will still work, and you can open the folder as a vault in Obsidian later."
            alert.addButton(withTitle: "Use Anyway")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        }
        return url
    }
}

struct OnboardingView: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Welcome to Coach").font(.largeTitle.bold())
                Text("Your revision coach for an Obsidian vault.")
                    .font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                point("folder", "Everything lives in a **Coach/** folder in your vault. Subfolders are your subjects, topics and subtopics.")
                point("gauge.with.dots.needle.33percent", "Rate each **file** 1–5. Low means shaky or too important to forget, so it comes back sooner. Folders show the averages.")
                point("calendar.badge.clock", "Coach records when you added and last revised each file, and schedules the next review.")
                point("menubar.rectangle", "See what's due from the menu bar, and get a daily reminder.")
            }
            .frame(maxWidth: 460)
            Button {
                if let url = VaultPicker.choose() { store.open(url) }
            } label: {
                Text("Choose Obsidian Vault…").padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func point(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(.tint)
            Text(text)
        }
    }
}

struct SettingsView: View {
    @Environment(VaultStore.self) private var store
    @AppStorage(Notifier.enabledKey) private var reminderEnabled = true
    @AppStorage(Notifier.minutesKey) private var reminderMinutes = 9 * 60
    @AppStorage(Notifier.eveningEnabledKey) private var eveningEnabled = false
    @AppStorage(Notifier.eveningMinutesKey) private var eveningMinutes = 19 * 60
    @State private var permission: UNAuthorizationStatus = .notDetermined
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?
    @AppStorage(StudyBuddy.enabledKey) private var buddyEnabled = true
    @AppStorage(StudyBuddy.speciesKey) private var buddySpecies = "random"
    @AppStorage(StudyBuddy.intervalKey) private var buddyHours = 2
    @AppStorage(VaultStore.coachFolderKey) private var coachFolder = "Coach"

    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date())!
        } set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Open Coach at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        guard on != LoginItem.isEnabled else { return }
                        loginError = LoginItem.set(on)
                        loginStatus = LoginItem.status
                        openAtLogin = LoginItem.isEnabled
                    }
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("macOS needs you to allow Coach in Login Items.")
                            .font(.caption).foregroundStyle(.orange)
                        Button("Open Login Items…") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("General")
            } footer: {
                Text("Starts quietly in the menu bar when you log in, so reminders always have today's real list.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Stepper(value: $store.dailyGoal, in: 0...50) {
                    LabeledContent("Daily goal", value: store.dailyGoal == 0 ? "Off" : "\(store.dailyGoal) file\(store.dailyGoal == 1 ? "" : "s") a day")
                }
            } header: {
                Text("Revising")
            } footer: {
                Text(store.dailyGoal == 0
                     ? "Today shows only files that are due, so some days may have nothing."
                     : "Today always has \(store.dailyGoal) files: the due ones by priority, topped up with files that are nearly due. If more are due, the most important come first and the rest wait. Files you revise early get a slightly shorter boost.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Study buddy walks across the screen to remind me", isOn: $buddyEnabled)
                Picker("Buddy", selection: $buddySpecies) {
                    Text("Surprise me").tag("random")
                    ForEach(StudyBuddy.Species.allCases) { Text($0.name).tag($0.rawValue) }
                }
                .disabled(!buddyEnabled)
                Picker("Visits", selection: $buddyHours) {
                    Text("Every hour").tag(1)
                    Text("Every 2 hours").tag(2)
                    Text("Every 3 hours").tag(3)
                    Text("Every 4 hours").tag(4)
                }
                .disabled(!buddyEnabled)
                Button("Call Buddy Now") { StudyBuddy.shared.visit() }
            } header: {
                Text("Study buddy")
            } footer: {
                Text("Visits only while today's list isn't done, while you're using the Mac, during the day, and never over full-screen apps. Click it to pet it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Vault") {
                LabeledContent("Folder") {
                    Text(store.vaultURL?.path ?? "None").lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Button("Change…") { if let url = VaultPicker.choose() { store.open(url) } }
                    if let url = store.vaultURL {
                        Button("Reveal in Finder") { NSWorkspace.shared.open(url) }
                    }
                }
                TextField("Coach folder", text: $coachFolder)
                    .onSubmit { if let url = store.vaultURL { store.open(url) } }
                Text("Coach only looks inside \(coachFolder.isEmpty ? "Coach" : coachFolder)/. Its subfolders are your subjects, topics and subtopics.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Morning reminder of files due today", isOn: $reminderEnabled)
                DatePicker("Time", selection: time($reminderMinutes), displayedComponents: .hourAndMinute)
                    .disabled(!reminderEnabled)
                Toggle("Evening catch-up if files are still due", isOn: $eveningEnabled)
                DatePicker("Time", selection: time($eveningMinutes), displayedComponents: .hourAndMinute)
                    .disabled(!eveningEnabled)
                HStack {
                    Button("Send Test Notification") { Notifier.shared.sendTest(topics: store.topics) }
                        .disabled(!Notifier.shared.isAvailable || permission == .denied)
                    if permission == .denied {
                        Button("Allow in System Settings…") { Notifier.openSystemSettings() }
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Group {
                    if !Notifier.shared.isAvailable {
                        Text("Reminders only work when Coach runs as an installed .app.")
                    } else if permission == .denied {
                        Text("Notifications are turned off for Coach in System Settings, so no reminders will appear.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Click a reminder to start revising the most urgent file, or choose “Remind Me in 1 Hour”. Reminders are scheduled \(Notifier.daysAhead / 7) weeks ahead and arrive even when Coach isn't running\(openAtLogin ? "" : "; turn on “Open Coach at login” to keep them up to date").")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onChange(of: reminderEnabled) { store.scanNow() }
        .onChange(of: reminderMinutes) { store.scanNow() }
        .onChange(of: eveningEnabled) { store.scanNow() }
        .onChange(of: eveningMinutes) { store.scanNow() }
        .task {
            permission = await Notifier.shared.authorizationStatus()
            loginStatus = LoginItem.status
            openAtLogin = LoginItem.isEnabled
        }
    }
}
