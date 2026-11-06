import AppKit
import CoachCore
import SwiftUI

struct MenuBarView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var quickTitle = ""
    @State private var quickConfidence = 3
    @State private var added: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.vaultURL == nil {
                Text("Coach").font(.headline)
                Text("Choose your Obsidian vault to get started.").foregroundStyle(.secondary)
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
                Button { openSettings(); NSApp.activate(ignoringOtherApps: true) } label: { Image(systemName: "gearshape") }
                    .help("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit Coach")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Coach").font(.headline)
                Text(store.dueCount == 0 ? "All caught up" : "\(store.dueCount) topic\(store.dueCount == 1 ? "" : "s") due")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.dueCount > 0 {
                Button("Start Review") {
                    showMain()
                    store.presentedSheet = .review
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var dueList: some View {
        let due = store.dueTopics
        return VStack(alignment: .leading, spacing: 8) {
            if due.isEmpty {
                Label("Nothing due today", systemImage: "checkmark.seal").foregroundStyle(.secondary)
            }
            ForEach(due.prefix(6)) { topic in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle().fill(Confidence.color(topic.confidence)).frame(width: 7, height: 7)
                        Button(topic.title) { openWindow.revise(topic.id) }
                            .buttonStyle(.plain)
                            .help("Open the revision page")
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
            Text("Quick add").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("New topic…", text: $quickTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            HStack(spacing: 4) {
                ConfidencePicker(selection: $quickConfidence, compact: true)
                Button("Add", action: add)
                    .disabled(quickTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let added {
                Text("Added “\(added)”").font(.caption).foregroundStyle(.green)
            }
        }
    }

    private func add() {
        let title = quickTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let subject = UserDefaults.standard.string(forKey: VaultStore.lastSubjectKey) ?? "Inbox"
        if store.createTopic(title: title, subject: subject, confidence: quickConfidence,
                             recallQuestion: "", notes: "", lastRevised: nil) != nil {
            added = title
            quickTitle = ""
        }
    }

    private func showMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
