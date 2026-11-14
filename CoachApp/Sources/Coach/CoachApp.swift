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
        WindowGroup("Revise", id: "revise", for: ReviseTarget.self) { $target in
            RevisePage(target: $target)
                .environment(store)
                .frame(minWidth: 640, minHeight: 560)
        }
        .defaultSize(width: 880, height: 860)

        // Note editor: one window per file, opened with Edit Note (⌘E).
        WindowGroup("Edit Note", id: "editor", for: String.self) { $topicID in
            NoteEditorWindow(topicID: $topicID)
                .environment(store)
                .frame(minWidth: 620, minHeight: 480)
        }
        .defaultSize(width: 980, height: 780)

        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            // Icon plus the number of files due, drawn as one template image so it always renders.
            Image(nsImage: MenuBarIcon.image(dueCount: store.vaultURL == nil ? 0 : store.todayCount))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAtLogin = MainActor.assumeIsolated { LoginItem.launchedAtLogin() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        MainActor.assumeIsolated {
            Notifier.shared.setUp()
            Notifier.shared.runLaunchTestIfRequested()
        }
        if launchedAtLogin {
            // Started at login: stay quietly in the menu bar instead of opening the main window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("main") == true {
                    window.close()
                }
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Closing the window keeps Coach alive in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct CoachCommands: Commands {
    let store: VaultStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Lets a clicked reminder open the revision page even when no Coach window is open.
        let _ = Notifier.shared.attach(store: store, openWindow: openWindow)
        let _ = StudyBuddy.shared.attach(store: store, openWindow: openWindow)
        // Replaces the default "New Window" item, which would open an empty revise window.
        CommandGroup(replacing: .newItem) {
            Button("New File…") {
                openWindow(id: "main")
                store.presentedSheet = .addTopic(folder: nil)
            }
            .keyboardShortcut("n")
            .disabled(store.vaultURL == nil)

            Button("New Folder…") {
                openWindow(id: "main")
                store.presentedSheet = .newFolder(parent: [])
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(store.vaultURL == nil)

            Button("Revise Selected File") {
                if let id = store.selectedTopicID { openWindow.revise(id) }
            }
            .keyboardShortcut("o")
            .disabled(store.topic(id: store.selectedTopicID) == nil)

            Button("Start Review") {
                openWindow(id: "main")
                store.presentedSheet = .review
            }
            .keyboardShortcut("r")
            .disabled(store.reviewQueue.isEmpty)

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
