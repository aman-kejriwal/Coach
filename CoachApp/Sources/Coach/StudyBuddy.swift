import AppKit
import CoachCore
import SwiftUI

/// A small cat, dog, panda, bee or bunny that walks (the bee flies, the bunny hops) across the bottom of the screen now and then while today's
/// list isn't done, sits down in the middle and asks you to revise. It only visits while you're at
/// the Mac (not idle), during the day, and never over full-screen apps.
@MainActor
final class StudyBuddy {
    static let shared = StudyBuddy()

    static let enabledKey = "buddyEnabled"
    static let speciesKey = "buddySpecies"        // "cat", "dog", "panda", "bee", "bunny" or "random"
    static let intervalKey = "buddyIntervalHours" // hours between visits

    enum Species: String, CaseIterable, Identifiable {
        case cat, dog, panda, bee, bunny
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
        var sound: String { ["Meow!", "Woof!", "Psst!", "Bzz!", "Boing!"][Self.allCases.firstIndex(of: self)!] }
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
    var interval: TimeInterval { Double(UserDefaults.standard.object(forKey: Self.intervalKey) as? Int ?? 2) * 3600 }

    private weak var store: VaultStore?
    private var openWindow: OpenWindowAction?
    private var clock: Timer?
    /// First visit about 10 minutes after launch.
    private lazy var lastVisit = Date().addingTimeInterval(-interval + 600)

    private var panel: NSPanel?
    private var mover: Timer?
    private let model = BuddyModel()
    private var phase = Phase.walkingIn
    private var lastStep = Date()
    private var stopX: CGFloat = 0
    private var endX: CGFloat = 0
    private var speed: CGFloat = 75 // points per second
    private var restUntil = Date()

    private enum Phase { case walkingIn, resting, walkingOut }
    static let windowSize = NSSize(width: 300, height: 210)

    func attach(store: VaultStore, openWindow: OpenWindowAction) {
        self.store = store
        self.openWindow = openWindow
        guard clock == nil else { return }
        if CommandLine.arguments.contains("--buddy") { // `open -a Coach --args --buddy` for a demo visit
            Task { @MainActor in try? await Task.sleep(for: .seconds(2)); self.visit() }
        }
        clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { StudyBuddy.shared.tick() }
        }
    }

    // MARK: When to visit

    private func tick() {
        guard enabled, panel == nil, let store, store.todayCount > 0,
              Date().timeIntervalSince(lastVisit) >= interval, isDaytime, !isIdle else { return }
        visit()
    }

    /// From the morning reminder time (or 9:00) until 22:00.
    private var isDaytime: Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return minutes >= min(Notifier.shared.minutes, 9 * 60) && minutes < 22 * 60
    }

    /// No visits while you're away from the Mac (or the screen is locked).
    private var isIdle: Bool {
        guard let any = CGEventType(rawValue: ~0) else { return false }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any) > 300
    }

    // MARK: A visit

    /// Sends the buddy across the screen now (also from Settings and the menu bar).
    func visit() {
        guard panel == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        lastVisit = Date()
        let raw = UserDefaults.standard.string(forKey: Self.speciesKey) ?? "random"
        model.species = Species(rawValue: raw) ?? Species.allCases.randomElement()!
        model.message = message()
        model.showsButtons = false
        model.walking = true
        model.hopping = false
        model.heart = false

        let vf = screen.visibleFrame
        let size = Self.windowSize
        let fromLeft = Bool.random()
        model.facingRight = fromLeft
        let startX = fromLeft ? vf.minX - size.width : vf.maxX
        endX = fromLeft ? vf.maxX + 10 : vf.minX - size.width - 10
        stopX = vf.minX + vf.width * CGFloat.random(in: 0.3...0.7) - size.width / 2
        speed = 75
        phase = .walkingIn

        let p = BuddyPanel(contentRect: NSRect(origin: NSPoint(x: startX, y: vf.minY), size: size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: BuddyView(
            model: model,
            revise: { [weak self] in self?.revise() },
            later: { [weak self] in self?.later() },
            pet: { [weak self] in self?.pet() }))
        p.orderFrontRegardless()
        panel = p

        lastStep = Date()
        mover = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated { StudyBuddy.shared.step() }
        }
    }

    private func step() {
        guard let panel else { return }
        let now = Date()
        let dt = CGFloat(now.timeIntervalSince(lastStep))
        lastStep = now
        var x = panel.frame.origin.x

        switch phase {
        case .walkingIn:
            let dir: CGFloat = stopX > x ? 1 : -1
            x += dir * speed * dt
            if (dir > 0 && x >= stopX) || (dir < 0 && x <= stopX) {
                x = stopX
                phase = .resting
                restUntil = now.addingTimeInterval(9)
                withAnimation(.spring(duration: 0.35)) {
                    model.walking = false
                    model.showsButtons = true
                }
            }
        case .resting:
            if now >= restUntil { leave(message: nil) }
        case .walkingOut:
            let dir: CGFloat = endX > x ? 1 : -1
            x += dir * speed * dt
            if (dir > 0 && x >= endX) || (dir < 0 && x <= endX) { finish(); return }
        }
        panel.setFrameOrigin(NSPoint(x: x, y: panel.frame.origin.y))
    }

    private func leave(message: String?, fast: Bool = false) {
        guard phase != .walkingOut else { return }
        phase = .walkingOut
        speed = fast ? 190 : 85
        withAnimation(.easeOut(duration: 0.2)) {
            model.showsButtons = false
            model.walking = true
            if let message { model.message = message }
        }
        // Keep walking the same way it came from.
        model.facingRight = endX > (panel?.frame.origin.x ?? 0)
    }

    private func finish() {
        mover?.invalidate()
        mover = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: Actions

    private func revise() {
        hop()
        Notifier.shared.startRevising()
        leave(message: "Yay! Happy watering! 💧", fast: true)
    }

    private func later() {
        lastVisit = Date()
        leave(message: "Okay, see you later!")
    }

    /// Clicking the buddy: a happy hop, and it stays a little longer.
    private func pet() {
        hop()
        if phase == .resting { restUntil = max(restUntil, Date().addingTimeInterval(4)) }
    }

    private func hop() {
        withAnimation(.spring(duration: 0.25)) { model.hopping = true; model.heart = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.25))
            withAnimation(.spring(duration: 0.3)) { model.hopping = false }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { model.heart = false }
        }
    }

    private func message() -> String {
        let sound = model.species.sound
        guard let store else { return "\(sound) Time to water the garden?" }
        let plan = store.plan
        let n = plan.today.count
        var options = ["\(sound) \(Garden.plants(n)) \(n == 1 ? "is" : "are") thirsty today. 💧"]
        if let first = plan.today.first { options.append("\(sound) Shall we water “\(first.title)”?") }
        if plan.doneToday > 0, plan.goal > 0 { options.append("\(sound) \(plan.doneToday) of \(plan.goal) watered. Keep going! 🌿") }
        if let weak = plan.today.first(where: { $0.confidence <= 2 }) { options.append("\(sound) “\(weak.title)” is starting to wilt… 🥀") }
        options.append("\(sound) Just five minutes in the garden?")
        return options.randomElement()!
    }
}

/// Lets the bubble's buttons work without bringing Coach to the front.
private final class BuddyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor @Observable
final class BuddyModel {
    var species = StudyBuddy.Species.cat
    var message = ""
    var walking = true
    var facingRight = true
    var showsButtons = false
    var hopping = false
    var heart = false
}

struct BuddyView: View {
    let model: BuddyModel
    let revise: () -> Void
    let later: () -> Void
    let pet: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            bubble
            ZStack(alignment: .top) {
                CritterView(species: model.species, walking: model.walking, happy: model.hopping || model.heart)
                    .frame(width: 112, height: 90)
                    .scaleEffect(x: model.facingRight ? 1 : -1)
                    .offset(y: model.hopping ? -16 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: pet)
                    .help("Pet me!")
                if model.heart {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .font(.title3)
                        .offset(x: model.facingRight ? 26 : -26, y: -22)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .frame(width: StudyBuddy.windowSize.width, height: StudyBuddy.windowSize.height)
    }

    private var bubble: some View {
        VStack(spacing: 8) {
            Text(model.message)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if model.showsButtons {
                HStack(spacing: 6) {
                    Button("Water Now", action: revise)
                        .buttonStyle(.borderedProminent)
                    Button("Later", action: later)
                }
                .controlSize(.small)
                .tint(Garden.leaf)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .foregroundStyle(Color(nsColor: .labelColor))
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: 250)
        .background(
            BubbleShape()
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
        )
        .overlay(BubbleShape().stroke(Color(nsColor: .separatorColor)))
        .padding(.bottom, 6)
    }
}

/// A rounded speech bubble with a little tail at the bottom.
struct BubbleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: 12)
        p.move(to: CGPoint(x: r.midX - 7, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY + 7))
        p.addLine(to: CGPoint(x: r.midX + 7, y: r.maxY))
        return p
    }
}

/// The buddy itself, drawn in code (facing right) in a 100 × 80 grid: walking legs, a wagging tail,
/// blinking eyes and a little bob.
struct CritterView: View {
    let species: StudyBuddy.Species
    var walking: Bool
    var happy = false

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                g.scaleBy(x: size.width / 100, y: size.height / 80)
                draw(&g, t: t)
            }
        }
    }

    private struct Palette {
        var body: Color, belly: Color, ear: Color, innerEar: Color, legs: Color, tail: Color
    }

    private var palette: Palette {
        switch species {
        case .cat:
            let orange = Color(red: 0.98, green: 0.69, blue: 0.38)
            return Palette(body: orange, belly: Color(red: 1, green: 0.93, blue: 0.82), ear: orange,
                           innerEar: Color(red: 1, green: 0.72, blue: 0.75), legs: orange, tail: orange)
        case .dog:
            let tan = Color(red: 0.94, green: 0.80, blue: 0.58)
            let brown = Color(red: 0.62, green: 0.42, blue: 0.27)
            return Palette(body: tan, belly: Color(red: 1, green: 0.95, blue: 0.86), ear: brown,
                           innerEar: brown, legs: tan, tail: tan)
        case .panda:
            let black = Color(white: 0.16)
            return Palette(body: .white, belly: .white, ear: black, innerEar: black, legs: black, tail: black)
        case .bee:
            let yellow = Color(red: 1.0, green: 0.82, blue: 0.25)
            return Palette(body: yellow, belly: yellow, ear: yellow, innerEar: yellow, legs: Color(white: 0.16), tail: yellow)
        case .bunny:
            let fur = Color(red: 0.93, green: 0.89, blue: 0.84)
            return Palette(body: fur, belly: .white, ear: fur, innerEar: Color(red: 1, green: 0.74, blue: 0.78),
                           legs: fur, tail: .white)
        }
    }

    private func draw(_ g: inout GraphicsContext, t: Double) {
        let pal = palette
        let outline = Color(white: 0.2)
        let phase = walking ? t * 9 : 0
        let swing = walking && species != .bunny ? sin(phase) : 0
        let bob: CGFloat = !walking ? 0
            : species == .bunny ? CGFloat(abs(sin(phase * 0.5))) * 5 // hop
            : CGFloat(abs(sin(phase))) * 1.6
        let blink = t.truncatingRemainder(dividingBy: 4.2) < 0.14
        let hx: CGFloat = 76, hy: CGFloat = 30 - bob

        func shape(_ p: Path, _ fill: Color, line: CGFloat = 1.6) {
            g.fill(p, with: .color(fill))
            g.stroke(p, with: .color(outline), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        }
        func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, angle: Double = 0) -> Path {
            Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: cx, y: cy)))
        }
        func leg(_ x: CGFloat, _ angle: Double, _ color: Color) {
            let p = Path(roundedRect: CGRect(x: -4.2, y: 0, width: 8.4, height: 18), cornerRadius: 4.2)
                .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: x, y: 54 - bob * 0.5)))
            shape(p, color)
        }
        func thickStroke(_ p: Path, _ color: Color, width: CGFloat) {
            g.stroke(p, with: .color(outline), style: StrokeStyle(lineWidth: width + 3.2, lineCap: .round))
            g.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }

        func face(hx: CGFloat, hy: CGFloat) {
            let eyes = [CGPoint(x: hx - 6.5, y: hy - 1), CGPoint(x: hx + 6.5, y: hy - 1)]
            if species == .panda {
                g.fill(ellipse(eyes[0].x - 0.5, eyes[0].y + 0.5, 9, 11.5, angle: 0.45), with: .color(Color(white: 0.16)))
                g.fill(ellipse(eyes[1].x + 0.5, eyes[1].y + 0.5, 9, 11.5, angle: -0.45), with: .color(Color(white: 0.16)))
            }
            for e in eyes {
                if blink {
                    var lid = Path()
                    lid.move(to: CGPoint(x: e.x - 2.2, y: e.y))
                    lid.addQuadCurve(to: CGPoint(x: e.x + 2.2, y: e.y), control: CGPoint(x: e.x, y: e.y + 1.6))
                    g.stroke(lid, with: .color(species == .panda ? .white : outline), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                } else if happy {
                    var smile = Path() // ^ ^ eyes
                    smile.move(to: CGPoint(x: e.x - 2.4, y: e.y + 1))
                    smile.addQuadCurve(to: CGPoint(x: e.x + 2.4, y: e.y + 1), control: CGPoint(x: e.x, y: e.y - 2.6))
                    g.stroke(smile, with: .color(species == .panda ? .white : outline), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                } else {
                    g.fill(ellipse(e.x, e.y, 4, 5), with: .color(species == .panda ? .white : Color(white: 0.12)))
                    if species == .panda { g.fill(ellipse(e.x, e.y + 0.3, 2.4, 3), with: .color(Color(white: 0.12))) }
                    g.fill(ellipse(e.x + 0.8, e.y - 1, 1.3, 1.3), with: .color(.white))
                }
            }
            // Blush.
            for x in [hx - 10.5, hx + 10.5] {
                g.fill(ellipse(x, hy + 5, 5, 3), with: .color(Color(red: 1, green: 0.55, blue: 0.6).opacity(0.55)))
            }
            // Nose and mouth.
            let ny = hy + 4.5
            switch species {
            case .bee:
                break
            case .bunny:
                g.fill(ellipse(hx, ny - 0.3, 3.6, 2.6), with: .color(Color(red: 1, green: 0.55, blue: 0.62)))
            case .cat:
                var nose = Path()
                nose.move(to: CGPoint(x: hx - 1.8, y: ny - 1))
                nose.addLine(to: CGPoint(x: hx + 1.8, y: ny - 1))
                nose.addLine(to: CGPoint(x: hx, y: ny + 1))
                nose.closeSubpath()
                g.fill(nose, with: .color(Color(red: 1, green: 0.5, blue: 0.58)))
            default:
                g.fill(ellipse(hx, ny, species == .dog ? 5 : 4, species == .dog ? 3.4 : 2.8), with: .color(Color(white: 0.14)))
            }
            if species == .dog && happy {
                g.fill(Path(roundedRect: CGRect(x: hx - 2, y: ny + 2.5, width: 4, height: 5), cornerRadius: 2),
                       with: .color(Color(red: 1, green: 0.45, blue: 0.5)))
            }
            var mouth = Path()
            mouth.move(to: CGPoint(x: hx - 3, y: ny + 2))
            mouth.addQuadCurve(to: CGPoint(x: hx, y: ny + 2.2), control: CGPoint(x: hx - 1.5, y: ny + 4))
            mouth.addQuadCurve(to: CGPoint(x: hx + 3, y: ny + 2), control: CGPoint(x: hx + 1.5, y: ny + 4))
            g.stroke(mouth, with: .color(outline), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

            if species == .cat || species == .bunny { // whiskers
                for (from, to) in [((hx - 12, ny), (hx - 21, ny - 2)), ((hx - 12, ny + 2), (hx - 21, ny + 3.5)),
                                   ((hx + 12, ny), (hx + 21, ny - 2)), ((hx + 12, ny + 2), (hx + 21, ny + 3.5))] {
                    var w = Path()
                    w.move(to: CGPoint(x: from.0, y: from.1))
                    w.addLine(to: CGPoint(x: to.0, y: to.1))
                    g.stroke(w, with: .color(outline.opacity(0.7)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
                }
            }
        }

        // The bee flies instead of walking: it hovers up and down, wings fluttering fast while it travels.
        if species == .bee {
            let hover = CGFloat(sin(t * (walking ? 5 : 2.4))) * 2.5 + (happy ? -4 : 0)
            let by: CGFloat = 40 + hover
            let flap = sin(t * (walking ? 38 : 16)) * 0.3

            // Shadow far below (it's in the air), shrinking a little as it rises.
            let sw = 40 + hover * 1.5
            g.fill(Path(ellipseIn: CGRect(x: 52 - sw / 2, y: 72, width: sw, height: 5)), with: .color(.black.opacity(0.08)))
            // Wings behind the body, slightly see-through.
            let wing = Color(red: 0.82, green: 0.93, blue: 1.0).opacity(0.85)
            shape(ellipse(38, by - 18, 18, 26, angle: -0.5 + flap), wing, line: 1.3)
            shape(ellipse(52, by - 20, 18, 28, angle: 0.35 - flap), wing, line: 1.3)
            // Stinger.
            var sting = Path()
            sting.move(to: CGPoint(x: 22, y: by - 3)); sting.addLine(to: CGPoint(x: 13, y: by + 1))
            sting.addLine(to: CGPoint(x: 22, y: by + 5)); sting.closeSubpath()
            shape(sting, Color(white: 0.2))
            // Tiny dangling legs.
            for x in [40.0, 50.0, 60.0] {
                var l = Path()
                l.move(to: CGPoint(x: x, y: by + 14)); l.addLine(to: CGPoint(x: x - 2, y: by + 21))
                g.stroke(l, with: .color(outline), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            // Striped body.
            let body = ellipse(44, by, 46, 32)
            g.fill(body, with: .color(pal.body))
            var inside = g
            inside.clip(to: body)
            for x in [30.0, 44.0] {
                inside.fill(Path(CGRect(x: x, y: by - 20, width: 7, height: 40)), with: .color(Color(white: 0.16)))
            }
            g.stroke(body, with: .color(outline), lineWidth: 1.6)
            // Antennae, bouncing a little.
            let wobble = CGFloat(sin(t * 6)) * 1.5
            for (dx, tipx) in [(-5.0, 64.0), (5.0, 86.0)] {
                let tip = CGPoint(x: tipx, y: by - 38 + wobble)
                var a = Path()
                a.move(to: CGPoint(x: 76 + dx, y: by - 22))
                a.addQuadCurve(to: tip, control: CGPoint(x: 76 + dx * 1.6, y: by - 34))
                g.stroke(a, with: .color(outline), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                g.fill(ellipse(tip.x, tip.y, 4.5, 4.5), with: .color(Color(white: 0.16)))
            }
            // Head and face.
            shape(ellipse(76, by - 6, 32, 30), pal.body)
            face(hx: 76, hy: by - 6)
            return
        }

        // Shadow.
        g.fill(Path(ellipseIn: CGRect(x: 24, y: 71, width: 60, height: 6)), with: .color(.black.opacity(0.13)))

        // Tail (behind the body).
        switch species {
        case .cat:
            let wag = sin(t * 2.6) * 0.22
            var p = Path()
            p.move(to: .zero)
            p.addQuadCurve(to: CGPoint(x: -14, y: -24), control: CGPoint(x: -20, y: 0))
            thickStroke(p.applying(CGAffineTransform(rotationAngle: wag).concatenating(CGAffineTransform(translationX: 28, y: 44 - bob))),
                        pal.tail, width: 6.5)
        case .dog:
            let wag = sin(t * (happy ? 22 : 13)) * 0.45
            var p = Path()
            p.move(to: .zero)
            p.addQuadCurve(to: CGPoint(x: -12, y: -14), control: CGPoint(x: -12, y: -2))
            thickStroke(p.applying(CGAffineTransform(rotationAngle: wag).concatenating(CGAffineTransform(translationX: 27, y: 42 - bob))),
                        pal.tail, width: 6)
        case .panda:
            shape(ellipse(25, 43 - bob, 10, 10), pal.tail)
        case .bunny: // fluffy cotton tail
            shape(ellipse(24, 42 - bob, 13, 13), pal.tail)
        case .bee:
            break
        }

        // Far legs (a touch darker), body, near legs.
        let far = species == .panda ? pal.legs : pal.legs.opacity(0.85)
        if species == .bunny { // big hind foot tucked under the back, small front paw
            shape(ellipse(35, 63 - bob, 18, 8), far)
            leg(66, swing * 0.38, far)
        } else {
            leg(36, -swing * 0.38, far)
            leg(66, swing * 0.38, far)
        }

        let body = species == .bunny ? ellipse(48, 48 - bob, 50, 32) : ellipse(50, 47 - bob, 54, 30)
        shape(body, pal.body)
        var inside = g
        inside.clip(to: body)
        if species == .panda {
            inside.fill(Path(CGRect(x: 55, y: 25, width: 15, height: 50)), with: .color(Color(white: 0.16)))
        } else {
            inside.fill(ellipse(52, 58 - bob, 34, 14), with: .color(pal.belly))
        }
        g.stroke(body, with: .color(outline), lineWidth: 1.6)

        if species == .bunny {
            shape(ellipse(39, 64 - bob, 18, 8), pal.legs)
            leg(72, 0, pal.legs)
        } else {
            leg(42, swing * 0.38, pal.legs)
            leg(72, -swing * 0.38, pal.legs)
        }

        // Ears behind the head (cat, panda).
        switch species {
        case .cat:
            for (a, b, c) in [(CGPoint(x: 62, y: 22), CGPoint(x: 64, y: 5), CGPoint(x: 75, y: 15)),
                              (CGPoint(x: 77, y: 15), CGPoint(x: 88, y: 5), CGPoint(x: 90, y: 22))] {
                var ear = Path(); ear.move(to: a); ear.addLine(to: b); ear.addLine(to: c); ear.closeSubpath()
                shape(ear.offsetBy(dx: 0, dy: -bob), pal.ear)
                var inner = Path()
                inner.move(to: CGPoint(x: (a.x * 2 + b.x) / 3, y: (a.y + b.y * 2) / 3 + 3))
                inner.addLine(to: CGPoint(x: b.x, y: b.y + 4))
                inner.addLine(to: CGPoint(x: (c.x * 2 + b.x) / 3, y: (c.y + b.y * 2) / 3 + 3))
                g.fill(inner.offsetBy(dx: 0, dy: -bob), with: .color(pal.innerEar))
            }
        case .panda:
            shape(ellipse(63, 16 - bob, 12, 12), pal.ear)
            shape(ellipse(89, 16 - bob, 12, 12), pal.ear)
        case .bunny: // long upright ears; the right one flops over when happy
            let tilt = happy ? 0.55 : 0.12 + (walking ? sin(phase * 0.5) * 0.08 : 0)
            shape(ellipse(69, 6 - bob, 10, 28, angle: -0.18), pal.ear)
            g.fill(ellipse(69, 7 - bob, 5, 20, angle: -0.18), with: .color(pal.innerEar))
            shape(ellipse(84, 6 - bob, 10, 28, angle: tilt), pal.ear)
            g.fill(ellipse(84, 7 - bob, 5, 20, angle: tilt), with: .color(pal.innerEar))
        case .dog, .bee:
            break
        }

        // Head.
        shape(ellipse(hx, hy, 36, 33), species == .dog ? pal.body : pal.body)
        if species == .cat { // forehead stripes
            for dx in [-4.0, 0, 4.0] {
                var s = Path()
                s.move(to: CGPoint(x: hx + CGFloat(dx), y: hy - 15))
                s.addLine(to: CGPoint(x: hx + CGFloat(dx) * 0.8, y: hy - 10.5))
                g.stroke(s, with: .color(Color(red: 0.86, green: 0.5, blue: 0.22)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }
        if species == .dog { // floppy ears over the sides, flapping a little while walking
            let flap = walking ? sin(phase) * 0.12 : 0
            shape(ellipse(60, hy + 2, 11, 21, angle: 0.35 + flap), pal.ear)
            shape(ellipse(92, hy + 2, 11, 21, angle: -0.35 - flap), pal.ear)
        }

        face(hx: hx, hy: hy)
    }
}
