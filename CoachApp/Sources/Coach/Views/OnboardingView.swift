import AppKit
import CoachCore
import SwiftUI

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
                point("folder", "Topics are notes in your vault, under a **Coach/** folder.")
                point("gauge.with.dots.needle.33percent", "Rate confidence **1–5**. Low means shaky or too important to forget, so it comes back sooner.")
                point("calendar.badge.clock", "Coach records when you added and last revised each topic, and schedules the next review.")
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
    @AppStorage(VaultStore.coachFolderKey) private var coachFolder = "Coach"

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: Date())!
        } set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            reminderMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
        }
    }

    var body: some View {
        Form {
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
                TextField("New topics folder", text: $coachFolder)
                Text("New topics are saved in \(coachFolder.isEmpty ? "Coach" : coachFolder)/<Subject>/. Tracked notes can live anywhere in the vault.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Daily reminder") {
                Toggle("Remind me about due topics", isOn: $reminderEnabled)
                DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .disabled(!reminderEnabled)
                if !Notifier.shared.isAvailable {
                    Text("Reminders only work when Coach runs as an installed .app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onChange(of: reminderEnabled) { store.scanNow() }
        .onChange(of: reminderMinutes) { store.scanNow() }
    }
}
