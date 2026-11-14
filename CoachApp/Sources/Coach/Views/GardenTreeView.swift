import CoachCore
import SwiftUI

/// What the Garden Overview tree draws: one branch per subject (top-level folder), one leaf per file.
struct GardenTreeModel: Equatable {
    enum LeafState: Equatable { case unwatered, healthy, thirsty, wilting }

    struct Leaf: Identifiable, Equatable {
        let id: String
        let title: String
        let confidence: Int
        let state: LeafState
    }

    struct Branch: Identifiable, Equatable {
        let path: [String]
        let name: String
        let leaves: [Leaf]
        var id: String { path.joined(separator: "/") }
    }

    var branches: [Branch]
    /// Files directly inside the Coach folder: they grow on a small shoot at the top of the trunk.
    var crownLeaves: [Leaf]
    var goalMet: Bool

    var allLeaves: [Leaf] { branches.flatMap(\.leaves) + crownLeaves }

    /// 0…1. Average growth stage, pulled down by wilting plants. Sets how big and full the tree is.
    var health: Double { Self.health(allLeaves) }

    static func health(_ leaves: [Leaf]) -> Double {
        guard !leaves.isEmpty else { return 0 }
        let avg = Double(leaves.map(\.confidence).reduce(0, +)) / Double(leaves.count)
        let wilting = Double(leaves.filter { $0.state == .wilting }.count) / Double(leaves.count)
        return min(1, max(0, (avg - 1) / 4 - wilting * 0.3))
    }
}

/// The Garden Overview picture: a tree whose branches are your subjects and whose leaves are your files.
struct GardenTreeView: View {
    let model: GardenTreeModel
    var onBranch: ([String]) -> Void = { _ in }
    var onLeaf: (String) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let layout = TreeLayout(model: model, size: geo.size)
            ZStack(alignment: .topLeading) {
                TreeSky(goalMet: model.goalMet, dark: scheme == .dark)
                Canvas { g, _ in layout.drawWood(&g, dark: scheme == .dark) }
                    .animation(.easeInOut(duration: 0.8), value: model)
                ForEach(layout.placed) { p in
                    LeafView(leaf: p.leaf, size: p.size)
                        .rotationEffect(.radians(p.angle), anchor: .bottom)
                        .animation(.spring(duration: 0.8, bounce: 0.35), value: p.angle)
                        .position(x: p.base.x, y: p.base.y - p.size / 2)
                        .onTapGesture { onLeaf(p.leaf.id) }
                        .help(p.leaf.title)
                        .transition(.scale(scale: 0.1, anchor: .bottom).combined(with: .opacity))
                }
                ForEach(layout.tips) { tip in
                    Text(tip.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                        .fixedSize()
                        .position(tip.label)
                        .onTapGesture { onBranch(tip.path) }
                        .help("Open \(tip.name)")
                }
                if model.allLeaves.isEmpty {
                    Text("Plant your first file and watch your tree grow")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: geo.size.width * 0.8)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.2)
                }
            }
        }
        .clipped()
    }
}

// MARK: - Layout

private struct TreeLayout {
    struct Limb { let start: CGPoint; let control: CGPoint; let end: CGPoint; let width: CGFloat; var leafCount = 0; var health = 0.0 }
    struct Placed: Identifiable {
        let leaf: GardenTreeModel.Leaf
        let stem: CGPoint      // where the twig leaves the branch
        let base: CGPoint      // where the leaf starts
        let angle: Double      // 0 = pointing up, clockwise positive
        let size: CGFloat
        var id: String { leaf.id }
    }
    struct Tip: Identifiable { let path: [String]; let name: String; let label: CGPoint; var id: String { path.joined(separator: "/") } }

    let size: CGSize
    let groundY: CGFloat
    let trunkBase: CGPoint
    let trunkTop: CGPoint
    let trunkWidth: CGFloat
    var limbs: [Limb] = []
    var placed: [Placed] = []
    var tips: [Tip] = []
    var fallen: [(CGPoint, Double)] = []
    var leafSize: CGFloat = 16

    init(model: GardenTreeModel, size: CGSize) {
        self.size = size
        let w = size.width, h = size.height
        let health = model.health
        let empty = model.allLeaves.isEmpty
        groundY = h * 0.86
        trunkBase = CGPoint(x: w / 2, y: groundY)
        trunkTop = CGPoint(x: w / 2, y: groundY - h * (empty ? 0.14 : 0.36 + 0.12 * health))
        trunkWidth = empty ? 8 : max(14, min(w, h) * (0.05 + 0.03 * health))
        let leafSize = max(15, min(26, min(w, h) * 0.058))
        self.leafSize = leafSize

        let branches = model.branches
        let n = branches.count
        for (i, branch) in branches.enumerated() {
            let frac = n == 1 ? 0.75 : 0.32 + 0.6 * Double(i) / Double(n - 1)
            let start = CGPoint(x: w / 2, y: trunkBase.y + (trunkTop.y - trunkBase.y) * frac)
            let side: CGFloat = n == 1 ? 1 : (i % 2 == 0 ? -1 : 1)
            let fill = min(1, Double(branch.leaves.count) / 8)
            let reach = w * (0.24 + 0.14 * (1 - frac)) * (0.75 + 0.25 * fill) * (0.85 + 0.15 * health)
            let rise = h * (0.07 + 0.12 * frac)
            var end = CGPoint(x: start.x + side * reach, y: start.y - rise)
            end.x = min(max(end.x, w * 0.13), w * 0.87)
            end.y = max(end.y, h * 0.12)
            let control = CGPoint(x: start.x + side * reach * 0.55, y: start.y - rise * 0.05)
            let limb = Limb(start: start, control: control, end: end, width: 3 + 5 * fill,
                            leafCount: branch.leaves.count, health: GardenTreeModel.health(branch.leaves))
            limbs.append(limb)
            place(branch.leaves, on: limb, leafSize: leafSize)
            tips.append(Tip(path: branch.path, name: branch.name,
                            label: CGPoint(x: end.x, y: end.y - leafSize * (1.4 + 0.12 * sqrt(Double(branch.leaves.count))))))
        }
        if !model.crownLeaves.isEmpty || empty {
            let top = CGPoint(x: trunkTop.x, y: trunkTop.y - h * (empty ? 0.04 : 0.10))
            let limb = Limb(start: trunkTop, control: CGPoint(x: trunkTop.x + 4, y: (trunkTop.y + top.y) / 2), end: top, width: 4,
                            leafCount: empty ? 0 : model.crownLeaves.count, health: GardenTreeModel.health(model.crownLeaves))
            limbs.append(limb)
            if empty {
                // A lone sprout: two leaves at the top.
                for (k, a) in [-0.9, 0.9].enumerated() {
                    let leaf = GardenTreeModel.Leaf(id: "sprout\(k)", title: "", confidence: 2, state: .healthy)
                    placed.append(Placed(leaf: leaf, stem: top, base: top, angle: a, size: leafSize * 1.4))
                }
            } else {
                place(model.crownLeaves, on: limb, leafSize: leafSize)
            }
        }

        // Fallen leaves on the ground, one per wilting plant (up to 10).
        let wilting = model.allLeaves.filter { $0.state == .wilting }.prefix(10)
        for leaf in wilting {
            let r = Self.unit(leaf.id, salt: 7)
            let x = w * (0.18 + 0.64 * r)
            fallen.append((CGPoint(x: x, y: groundY + 6 + 10 * Self.unit(leaf.id, salt: 3)), (r - 0.5) * 3))
        }
    }

    private mutating func place(_ leaves: [GardenTreeModel.Leaf], on limb: Limb, leafSize: CGFloat) {
        let count = leaves.count
        let spread = 1 + min(1.5, Double(count) / 14)
        for (k, leaf) in leaves.enumerated() {
            let jitter = (Self.unit(leaf.id, salt: 1) - 0.5) * 0.5
            let t = 0.22 + 0.78 * min(1, max(0, (Double(k) + 0.5 + jitter) / Double(count)))
            let p = Self.point(limb, t)
            let d = Self.tangent(limb, t)
            let len = max(0.001, hypot(d.x, d.y))
            let dir = CGPoint(x: d.x / len, y: d.y / len)
            let sideSign: CGFloat = k % 2 == 0 ? 1 : -1
            let normal = CGPoint(x: -dir.y * sideSign, y: dir.x * sideSign)
            let reach = (5 + 12 * Self.unit(leaf.id, salt: 2)) * spread
            let base = CGPoint(x: p.x + normal.x * reach, y: p.y + normal.y * reach)
            // Leaf points outward from the branch, a little forward along it.
            let out = CGPoint(x: normal.x + dir.x * 0.6, y: normal.y + dir.y * 0.6)
            var angle = atan2(Double(out.x), Double(-out.y))
            angle += (Self.unit(leaf.id, salt: 4) - 0.5) * 0.5
            // Thirsty leaves droop, wilting ones hang.
            let droop: Double = switch leaf.state {
            case .thirsty: 0.45
            case .wilting: 0.75
            default: 0
            }
            let down = angle >= 0 ? Double.pi : -Double.pi
            angle += (down - angle) * droop
            let s = leafSize * (leaf.state == .unwatered ? 0.7 : 0.85 + 0.06 * Double(leaf.confidence))
            placed.append(Placed(leaf: leaf, stem: p, base: base, angle: angle, size: s))
        }
    }

    // MARK: Drawing

    func drawWood(_ g: inout GraphicsContext, dark: Bool) {
        let w = size.width, h = size.height
        let bark = dark ? Color(red: 0.50, green: 0.37, blue: 0.26) : Color(red: 0.47, green: 0.33, blue: 0.22)
        let barkEdge = dark ? Color(red: 0.30, green: 0.21, blue: 0.14) : Color(red: 0.33, green: 0.22, blue: 0.14)

        // Hill.
        let hill = Path(ellipseIn: CGRect(x: -w * 0.25, y: groundY - h * 0.05, width: w * 1.5, height: h * 0.5))
        g.fill(hill, with: .linearGradient(
            Gradient(colors: dark ? [Color(red: 0.20, green: 0.32, blue: 0.18), Color(red: 0.12, green: 0.20, blue: 0.11)]
                                  : [Color(red: 0.58, green: 0.76, blue: 0.42), Color(red: 0.42, green: 0.62, blue: 0.32)]),
            startPoint: CGPoint(x: 0, y: groundY - h * 0.05), endPoint: CGPoint(x: 0, y: h)))
        // Soil around the roots.
        g.fill(Path(ellipseIn: CGRect(x: trunkBase.x - trunkWidth * 2.2, y: groundY - 5, width: trunkWidth * 4.4, height: 12)),
               with: .color(bark.opacity(0.55)))

        // Fallen leaves.
        for (p, a) in fallen {
            var leaf = LeafShape().path(in: CGRect(x: -5, y: -8, width: 10, height: 16))
            leaf = leaf.applying(CGAffineTransform(rotationAngle: a).concatenating(CGAffineTransform(translationX: p.x, y: p.y)))
            g.fill(leaf, with: .color(LeafView.wiltColor.opacity(0.85)))
        }

        // Canopy: a soft cloud of foliage behind each branch. Lush green when that subject is healthy,
        // dry yellow-brown when it's neglected.
        for limb in limbs where limb.leafCount > 0 {
            let lush = (0.36, 0.66, 0.30), dry = (0.80, 0.66, 0.34)
            let k = limb.health
            let color = Color(red: dry.0 + (lush.0 - dry.0) * k, green: dry.1 + (lush.1 - dry.1) * k, blue: dry.2 + (lush.2 - dry.2) * k)
            let radius = leafSize * (1.1 + 0.32 * sqrt(Double(limb.leafCount)))
            var canopy = Path()
            for t in [0.45, 0.7, 0.95] {
                let c = Self.point(limb, t)
                let r = radius * (0.75 + 0.25 * t)
                canopy.addEllipse(in: CGRect(x: c.x - r, y: c.y - r * 1.05, width: r * 2, height: r * 1.8))
            }
            g.fill(canopy, with: .color(color.opacity(dark ? 0.32 : 0.38)))
        }

        // Branches (behind the trunk's top so they look attached).
        for limb in limbs {
            var p = Path()
            p.move(to: limb.start)
            p.addQuadCurve(to: limb.end, control: limb.control)
            g.stroke(p, with: .color(barkEdge), style: StrokeStyle(lineWidth: limb.width + 2.5, lineCap: .round))
            g.stroke(p, with: .color(bark), style: StrokeStyle(lineWidth: limb.width, lineCap: .round))
        }
        // Twigs to each leaf.
        for leaf in placed where leaf.stem != leaf.base {
            var t = Path()
            t.move(to: leaf.stem)
            t.addLine(to: leaf.base)
            g.stroke(t, with: .color(barkEdge.opacity(0.8)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }

        // Trunk: tapered, with flared roots.
        let bw = trunkWidth, tw = max(5, trunkWidth * 0.45)
        var trunk = Path()
        trunk.move(to: CGPoint(x: trunkBase.x - bw * 0.95, y: trunkBase.y + 2))
        trunk.addQuadCurve(to: CGPoint(x: trunkTop.x - tw / 2, y: trunkTop.y),
                           control: CGPoint(x: trunkBase.x - bw * 0.35, y: (trunkBase.y + trunkTop.y) / 2 + 10))
        trunk.addLine(to: CGPoint(x: trunkTop.x + tw / 2, y: trunkTop.y))
        trunk.addQuadCurve(to: CGPoint(x: trunkBase.x + bw * 0.95, y: trunkBase.y + 2),
                           control: CGPoint(x: trunkBase.x + bw * 0.35, y: (trunkBase.y + trunkTop.y) / 2 + 10))
        trunk.closeSubpath()
        g.fill(trunk, with: .color(bark))
        g.stroke(trunk, with: .color(barkEdge), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        // Bark lines.
        for dx in [-0.25, 0.2] {
            var line = Path()
            let x = trunkBase.x + bw * CGFloat(dx)
            line.move(to: CGPoint(x: x, y: trunkBase.y - 6))
            line.addQuadCurve(to: CGPoint(x: trunkTop.x + tw * CGFloat(dx), y: trunkTop.y + (trunkBase.y - trunkTop.y) * 0.45),
                              control: CGPoint(x: x + 3, y: (trunkBase.y + trunkTop.y) / 2 + 20))
            g.stroke(line, with: .color(barkEdge.opacity(0.45)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
    }

    // MARK: Math

    static func point(_ l: Limb, _ t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * l.start.x + 2 * u * t * l.control.x + t * t * l.end.x,
                       y: u * u * l.start.y + 2 * u * t * l.control.y + t * t * l.end.y)
    }

    static func tangent(_ l: Limb, _ t: Double) -> CGPoint {
        CGPoint(x: 2 * (1 - t) * (l.control.x - l.start.x) + 2 * t * (l.end.x - l.control.x),
                y: 2 * (1 - t) * (l.control.y - l.start.y) + 2 * t * (l.end.y - l.control.y))
    }

    /// A stable 0…1 number for a file (the same every launch), so leaves never jump around.
    static func unit(_ s: String, salt: UInt64) -> Double {
        var h: UInt64 = 0xcbf29ce484222325 &+ salt &* 0x9E3779B97F4A7C15
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }
}

// MARK: - Pieces

/// A leaf pointing up, with its stalk at the bottom centre.
struct LeafShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX - r.width * 0.15, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX + r.width * 0.15, y: r.midY))
        p.closeSubpath()
        return p
    }
}

struct LeafView: View {
    let leaf: GardenTreeModel.Leaf
    let size: CGFloat
    @State private var bounce = false
    @State private var drop = false

    static let wiltColor = Color(red: 0.66, green: 0.44, blue: 0.24)

    private var fill: Color {
        switch leaf.state {
        case .unwatered: return Color(red: 0.80, green: 0.87, blue: 0.62)
        case .wilting: return Self.wiltColor
        case .thirsty: return Color(red: 0.80, green: 0.75, blue: 0.32)
        case .healthy:
            return [Color(red: 0.66, green: 0.80, blue: 0.34), Color(red: 0.50, green: 0.74, blue: 0.30),
                    Color(red: 0.34, green: 0.65, blue: 0.27), Color(red: 0.21, green: 0.54, blue: 0.24),
                    Color(red: 0.13, green: 0.44, blue: 0.20)][min(max(leaf.confidence, 1), 5) - 1]
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if leaf.state == .unwatered {
                // A closed bud.
                Ellipse()
                    .fill(fill)
                    .overlay(Ellipse().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.8))
                    .frame(width: size * 0.45, height: size * 0.6)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                LeafShape().fill(fill)
                LeafShape().stroke(Color.black.opacity(0.22), lineWidth: 0.8)
                Rectangle().fill(Color.white.opacity(0.35)).frame(width: 0.9, height: size * 0.7)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                if leaf.state == .healthy && leaf.confidence == 5 {
                    Blossom().frame(width: size * 0.62, height: size * 0.62).offset(y: -size * 0.3)
                }
            }
        }
        .frame(width: size * 0.62, height: size)
        .animation(.easeInOut(duration: 0.7), value: leaf)
        .scaleEffect(bounce ? 1.5 : 1, anchor: .bottom)
        .overlay(alignment: .top) {
            if drop {
                Image(systemName: "drop.fill")
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(Color(red: 0.30, green: 0.60, blue: 0.92))
                    .transition(.asymmetric(insertion: .offset(y: -size).combined(with: .opacity),
                                            removal: .opacity.combined(with: .scale(scale: 0.3))))
                    .offset(y: -size * 0.3)
            }
        }
        .onChange(of: leaf) { old, new in
            // Watered: it was dry (or never watered) and now it's healthy, or it grew a stage.
            let watered = (old.state != .healthy && new.state == .healthy) || new.confidence > old.confidence
            guard watered else { return }
            Task { @MainActor in
                withAnimation(.easeIn(duration: 0.35)) { drop = true }
                try? await Task.sleep(for: .seconds(0.35))
                withAnimation(.spring(duration: 0.3, bounce: 0.6)) { bounce = true; drop = false }
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation(.spring(duration: 0.5)) { bounce = false }
            }
        }
    }
}

/// A small pink five-petal flower for fully grown (stage 5) plants.
struct Blossom: View {
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Circle().fill(Color(red: 1.0, green: 0.72, blue: 0.80))
                    .frame(width: 5, height: 5)
                    .offset(y: -3)
                    .rotationEffect(.degrees(Double(i) * 72))
            }
            Circle().fill(Color(red: 1.0, green: 0.85, blue: 0.35)).frame(width: 3.5, height: 3.5)
        }
    }
}

/// Sky behind the tree: a warm sun once today's watering round is done, a soft cloud otherwise.
struct TreeSky: View {
    let goalMet: Bool
    let dark: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: dark
                               ? [Color(red: 0.10, green: 0.13, blue: 0.20), Color(red: 0.14, green: 0.18, blue: 0.16)]
                               : [Color(red: 0.80, green: 0.91, blue: 0.97), Color(red: 0.97, green: 0.96, blue: 0.88)],
                               startPoint: .top, endPoint: .bottom)
                if goalMet {
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 1, green: 0.86, blue: 0.40), Color(red: 1, green: 0.72, blue: 0.30)],
                                             center: .center, startRadius: 0, endRadius: 30))
                        .frame(width: 54, height: 54)
                        .shadow(color: Color(red: 1, green: 0.8, blue: 0.3).opacity(0.7), radius: 18)
                        .position(x: w * 0.82, y: h * 0.1)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    ZStack {
                        Ellipse().frame(width: 60, height: 22)
                        Ellipse().frame(width: 34, height: 26).offset(x: -8, y: -8)
                        Ellipse().frame(width: 26, height: 20).offset(x: 12, y: -6)
                    }
                    .foregroundStyle(Color.white.opacity(dark ? 0.12 : 0.85))
                    .position(x: w * 0.8, y: h * 0.1)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 1), value: goalMet)
        }
    }
}

// MARK: - From the vault

extension GardenTreeModel {
    /// One branch per subject (each folder directly inside Coach/), holding every file under it.
    init(tree: FolderNode, now: Date, goalMet: Bool) {
        func leaf(_ t: Topic) -> Leaf {
            let d = t.daysUntilDue(now: now)
            let state: LeafState = t.lastReviewed == nil ? .unwatered : d < 0 ? .wilting : d == 0 ? .thirsty : .healthy
            return Leaf(id: t.id, title: t.title, confidence: t.confidence, state: state)
        }
        // Oldest first, so newly planted files sprout at the tip and existing leaves stay put.
        func leaves(_ topics: [Topic]) -> [Leaf] {
            topics.sorted { ($0.created ?? .distantPast, $0.id) < ($1.created ?? .distantPast, $1.id) }.map(leaf)
        }
        self.init(
            branches: tree.children
                .filter { !$0.allFiles.isEmpty }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { Branch(path: $0.path, name: $0.name, leaves: leaves($0.allFiles)) },
            crownLeaves: leaves(tree.files),
            goalMet: goalMet)
    }
}

/// The Garden Overview page: the whole vault as one tree.
struct GardenOverviewView: View {
    @Environment(VaultStore.self) private var store
    @Binding var sidebar: SidebarItem?

    var body: some View {
        let plan = store.plan
        GardenTreeView(
            model: GardenTreeModel(tree: store.tree, now: store.now, goalMet: plan.goal > 0 && plan.isGoalMet),
            onBranch: { sidebar = .folder($0) },
            onLeaf: { store.selectedTopicID = $0 })
        .ignoresSafeArea(edges: .bottom)
    }
}
