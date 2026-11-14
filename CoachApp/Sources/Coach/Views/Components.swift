import CoachCore
import SwiftUI

struct ConfidenceBadge: View {
    let confidence: Int
    var showLabel = true

    var body: some View {
        HStack(spacing: 4) {
            Text(Garden.stageEmoji(confidence)).font(.caption)
            Text(showLabel ? Garden.stageName(confidence) : "\(confidence)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Confidence.color(confidence).opacity(0.15), in: Capsule())
        .foregroundStyle(Garden.stageColor(confidence))
        .help("\(confidence) · \(Garden.stageName(confidence)): \(Garden.stageDetail(confidence))")
    }
}

/// Five buttons, 1–5. Lower = shakier / more important = reviewed more often.
struct ConfidencePicker: View {
    @Binding var selection: Int
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(Confidence.range), id: \.self) { c in
                    ConfidenceButton(confidence: c, isSelected: selection == c, compact: compact) { selection = c }
                }
            }
            if !compact {
                Text(Garden.stageDetail(selection))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ConfidenceButton: View {
    let confidence: Int
    var isSelected = false
    var compact = false
    var shortcut = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(Garden.stageEmoji(confidence)).font(compact ? .callout : .title2)
                if !compact { Text("\(confidence) · \(Garden.stageName(confidence))").font(.caption2) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 3 : 7)
            .background(Confidence.color(confidence).opacity(isSelected ? 0.9 : 0.18), in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(isSelected ? Color.black : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(confidence) · \(Garden.stageName(confidence)): \(Garden.stageDetail(confidence))")
        .modifier(OptionalShortcut(key: shortcut ? Character("\(confidence)") : nil))
    }
}

private struct OptionalShortcut: ViewModifier {
    let key: Character?
    func body(content: Content) -> some View {
        if let key { content.keyboardShortcut(KeyEquivalent(key), modifiers: []) } else { content }
    }
}

struct DueLabel: View {
    let topic: Topic
    let now: Date

    var body: some View {
        Text(Garden.dueText(topic, now: now))
            .foregroundStyle(Garden.dueColor(topic, now: now))
    }
}

/// "Have you revised this before?" plus a date picker; used when adding or tracking a topic.
struct LastRevisedField: View {
    @Binding var hasRevised: Bool
    @Binding var date: Date

    var body: some View {
        Toggle("I've watered this before", isOn: $hasRevised)
        if hasRevised {
            DatePicker("Last watered", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
        }
    }
}

struct NotePreview: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(Self.render(text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .gardenCard(radius: 8)
    }

    static func render(_ md: String) -> AttributedString {
        (try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(md)
    }
}

/// Shown where a file's note would be when it has no text yet.
struct EmptyNotePrompt: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("🌱").font(.largeTitle)
            Text("Nothing planted here yet").font(.headline)
            Text("Write what you need to revise (key points, steps, examples, mistakes) so it can grow here next time.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: action) { Label("Write Notes", systemImage: "square.and.pencil") }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .gardenCard(radius: 8)
    }
}
