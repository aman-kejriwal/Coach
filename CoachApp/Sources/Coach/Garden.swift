import AppKit
import CoachCore
import SwiftUI

/// The Garden theme: every file is a plant, every folder a garden bed, and revising is watering.
/// This is presentation only (colours, names, wording). Scheduling lives in CoachCore and is unchanged.
enum Garden {
    // MARK: Palette (light / dark)

    private static func dynamic(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Main accent: fresh leaf green.
    static let leaf = dynamic((0.24, 0.55, 0.30), (0.45, 0.78, 0.50))
    /// Deep forest green, for strong text and "solid" plants.
    static let forest = dynamic((0.13, 0.38, 0.20), (0.36, 0.70, 0.42))
    /// Warm soil brown.
    static let soil = dynamic((0.47, 0.33, 0.22), (0.72, 0.56, 0.42))
    /// Terracotta: wilting / overdue.
    static let terracotta = dynamic((0.76, 0.33, 0.22), (0.93, 0.50, 0.38))
    /// Sun amber: thirsty / due today.
    static let sun = dynamic((0.85, 0.56, 0.12), (0.96, 0.72, 0.30))
    /// Water blue: the watering action.
    static let water = dynamic((0.20, 0.50, 0.75), (0.45, 0.70, 0.92))
    /// Soft card surface: cream in light mode, mossy charcoal in dark mode.
    static let card = dynamic((0.97, 0.96, 0.91), (0.15, 0.17, 0.14))
    /// Card border.
    static let cardEdge = dynamic((0.86, 0.84, 0.74), (0.26, 0.30, 0.24))

    // MARK: Plant stages (confidence 1–5)

    static func stageColor(_ c: Int) -> Color {
        [terracotta, sun, dynamic((0.60, 0.66, 0.20), (0.76, 0.82, 0.38)), leaf, forest][Confidence.clamp(c) - 1]
    }

    static func stageEmoji(_ c: Int) -> String {
        ["🌰", "🌱", "🌿", "🌷", "🌳"][Confidence.clamp(c) - 1]
    }

    static func stageName(_ c: Int) -> String {
        ["Seed", "Sprout", "Sapling", "Bloom", "Tree"][Confidence.clamp(c) - 1]
    }

    static func stageDetail(_ c: Int) -> String {
        [
            "Barely remember it, or can't afford to forget it. Watered very often.",
            "Shaky roots. Needs water again within a few days.",
            "Growing well. Normal watering.",
            "Healthy and flowering. Longer gaps between watering.",
            "Deep roots. Only the occasional check-in.",
        ][Confidence.clamp(c) - 1]
    }

    // MARK: Watering status (same dates as before, garden words)

    static func dueText(_ topic: Topic, now: Date) -> String {
        switch topic.daysUntilDue(now: now) {
        case ..<(-1): return "Wilting · \(-topic.daysUntilDue(now: now)) days dry"
        case -1: return "Wilting · 1 day dry"
        case 0: return "Thirsty today"
        case 1: return "Water tomorrow"
        case let d: return "Water in \(d) days"
        }
    }

    static func dueColor(_ topic: Topic, now: Date) -> Color {
        let d = topic.daysUntilDue(now: now)
        return d < 0 ? terracotta : d == 0 ? sun : .secondary
    }

    static func plants(_ n: Int) -> String { n == 1 ? "1 plant" : "\(n) plants" }
}

extension Confidence {
    static func color(_ c: Int) -> Color { Garden.stageColor(c) }
}

/// A rounded cream "garden card" background with a soft border.
struct GardenCard: ViewModifier {
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(Garden.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Garden.cardEdge))
    }
}

extension View {
    func gardenCard(radius: CGFloat = 12) -> some View { modifier(GardenCard(radius: radius)) }
}
