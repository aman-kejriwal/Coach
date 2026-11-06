import AppKit
import CoachCore
import SwiftUI

@main
struct CoachApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = VaultStore()

    var body: some Scene {
        Window("Coach", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 740)
        .commands { CoachCommands(store: store) }

        // Dedicated revision page: one window per topic, opened by double-click / "Revise Now".
        WindowGroup("Revise", id: "revise", for: String.self) { $topicID in
            RevisePage(topicID: $topicID)
                .environment(store)
                .frame(minWidth: 640, minHeight: 560)
        }
        .defaultSize(width: 880, height: 860)

        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            // Icon plus the number of topics due, always visible in the menu bar.
            let due = store.vaultURL == nil ? 0 : store.dueCount
            Text(due > 0 ? "\(Image(systemName: "brain.head.profile")) \(due)" : "\(Image(systemName: "brain.head.profile"))")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in Notifier.shared.requestAuthorization() }
    }

    /// Closing the window keeps Coach alive in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct CoachCommands: Commands {
    let store: VaultStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Replaces the default "New Window" item, which would open an empty revise window.
        CommandGroup(replacing: .newItem) {
            Button("New Topic…") {
                openWindow(id: "main")
                store.presentedSheet = .addTopic
            }
            .keyboardShortcut("n")
            .disabled(store.vaultURL == nil)

            Button("Revise Selected Topic") {
                if let id = store.selectedTopicID { openWindow.revise(id) }
            }
            .keyboardShortcut("o")
            .disabled(store.topic(id: store.selectedTopicID) == nil)

            Button("Start Review") {
                openWindow(id: "main")
                store.presentedSheet = .review
            }
            .keyboardShortcut("r")
            .disabled(store.dueCount == 0)

            Divider()

            Button("Refresh Vault") { store.scanNow() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.vaultURL == nil)

            // Separate from text-editing Undo (⌘Z) so typing in a field never reverts a review.
            Button(store.lastUndo.map { "Undo \($0.label)" } ?? "Undo Last Change") { store.undo() }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(store.lastUndo == nil)
        }
    }
}
