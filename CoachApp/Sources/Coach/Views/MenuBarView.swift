import AppKit
import CoachCore
import SwiftUI

struct MenuBarView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var quickTitle = ""
    @State private var quickConfidence = 3
    /// Quick-add needs a folder; nil = not chosen yet (Add stays disabled).
    @State private var quickFolder: [String]?
    @State private var added: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.vaultURL == nil {
                Text("Coach").font(.headline)
                Text("Choose your Obsidian vault to start your garden.").foregroundStyle(.secondary)
                Button("Open Coach") { showMain() }
            } else {
                header
                Divider()
                dueList
                Divider()
                quickAdd
            }
            Divider()
            HStack {
                Button("Open Coach") { showMain() }
                Spacer()
                Button { StudyBuddy.shared.visit() } label: { Image(systemName: "pawprint") }
                    .help("Call your study buddy")
                Button { openSettings(); NSApp.activate(ignoringOtherApps: true) } label: { Image(systemName: "gearshape") }
                    .help("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit Coach")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 340)
        .tint(Garden.leaf)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("🌱 Coach").font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !store.reviewQueue.isEmpty {
                Button("Start Watering") {
                    showMain()
                    store.presentedSheet = .review
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var subtitle: String {
        let plan = store.plan
        let n = plan.today.count
        if n > 0 {
            let goal = plan.goal > 0 ? " · \(min(plan.doneToday, plan.goal)) of \(plan.goal) watered" : ""
            return "\(Garden.plants(n)) to water today\(goal)"
        }
        if plan.isGoalMet { return plan.moreDue.isEmpty ? "The garden is watered" : "Round done · \(plan.moreDue.count) more thirsty" }
        return "Nothing is thirsty"
    }

    private var dueList: some View {
        let due = store.reviewQueue
        return VStack(alignment: .leading, spacing: 8) {
            if due.isEmpty {
                Label(store.plan.isGoalMet ? "The garden is watered 🌻" : "Nothing is thirsty today", systemImage: "leaf")
                    .foregroundStyle(.secondary)
            }
            ForEach(due.prefix(6)) { topic in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Garden.stageEmoji(topic.confidence))
                        Button(topic.title) { openWindow.revise(topic.id) }
                            .buttonStyle(.plain)
                            .help("Water this plant")
                        .lineLimit(1)
                        Spacer()
                        DueLabel(topic: topic, now: store.now).font(.caption2)
                    }
                    HStack(spacing: 4) {
                        ForEach(Array(Confidence.range), id: \.self) { c in
                            ConfidenceButton(confidence: c, compact: true) { store.review(topic, confidence: c) }
                        }
                    }
                }
            }
            if due.count > 6 {
                Text("+ \(due.count - 6) more").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick plant").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("New plant…", text: $quickTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            FolderPicker(title: "Bed", selection: $quickFolder)
                .controlSize(.small)
            HStack(spacing: 4) {
                ConfidencePicker(selection: $quickConfidence, compact: true)
                Button("Plant", action: add)
                    .disabled(quickTitle.trimmingCharacters(in: .whitespaces).isEmpty || quickFolder == nil)
            }
            if let added {
                Text("Planted “\(added)” 🌱").font(.caption).foregroundStyle(Garden.leaf)
            }
        }
    }

    private func add() {
        let title = quickTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let folder = quickFolder else { return }
        if store.createTopic(title: title, folder: folder, confidence: quickConfidence) != nil {
            added = title
            quickTitle = ""
        }
    }

    private func showMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
