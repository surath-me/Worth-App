import SwiftUI

/// The breakdown as bubbles, like the web app: groups at the top (area true to value), tap one to open it and its
/// entries pop out of it onto a honeycomb; the back button pulls them back in. A legend lists every bubble.
struct Bubbles: View {
    @Environment(Store.self) private var store
    @Environment(Prefs.self) private var prefs
    let onOpen: (Account) -> Void
    let onAdd: (String) -> Void
    @State private var level: String?            // an open group
    @State private var origin: CGPoint?          // where the opened group's bubble sat
    @State private var cameBack: String?         // the group we just left (it grows back first)
    // press and hold: the bubble sinks, then lifts and follows your finger; passing over another bubble takes its place
    @State private var drag: (id: String, start: CGPoint, now: CGPoint)?
    @State private var order: [String]?          // the order while dragging (saved on release)
    @GestureState private var pressing: String?

    struct Item: Identifiable, Equatable {
        let id: String; let name: String; let value: Double; let color: Color; let grad: String
        var liab = false; var group: String?; var account: Account?; var symbol: String?; var equity = false
    }

    var body: some View {
        let items = itemsNow
        VStack(alignment: .leading, spacing: 12) {
            header(items)
            GeometryReader { g in
                let P = layout(items, size: g.size)
                ZStack {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, x in
                        Bubble(item: x, r: P[i].r, at: P[i].c, from: start(for: x, i: i, P: P, size: g.size), delay: Double(i) * 0.04,
                               dragAt: drag?.id == x.id ? drag?.now : nil, pressing: pressing == x.id)
                            .zIndex(drag?.id == x.id ? 10 : 0)
                            .onTapGesture { tap(x, at: P[i].c) }
                            .gesture(reorder(x, items: items, P: P))
                    }
                }
                .coordinateSpace(name: "bub")
                .sensoryFeedback(.impact(weight: .medium), trigger: drag?.id) { _, new in new != nil }
                .sensoryFeedback(.selection, trigger: order)
                .id(level ?? "top")
                .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 0.85))))
            }
            .frame(height: 300)
            legend(items)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.card))
        .onChange(of: store.data.accounts) { if let l = level, store.accounts(in: Catalog.groups.first { $0.id == l }!).isEmpty { level = nil } }
    }

    // MARK: items

    private var itemsNow: [Item] {
        if let level, let g = Catalog.groups.first(where: { $0.id == level }) {
            return store.accounts(in: g).map { a in
                let t = Catalog.type(a.type)
                return Item(id: "a:" + a.id, name: a.name, value: max(0, store.conv(a.bal, a.cur)), color: t.color, grad: t.id,
                            liab: t.liab, account: a, symbol: Catalog.symbol(for: a))
            }.filter { $0.value > 0 }.sorted { $0.value > $1.value }.ordered(by: order ?? prefs.bubOrder[level])
        }
        let sp = store.liveSplit
        var out = sp.groups.map { Item(id: "g:" + $0.group.id, name: $0.group.name, value: $0.value, color: $0.group.color, grad: $0.group.id,
                                       group: $0.group.id, equity: $0.group.id == "property" && sp.netted) }
        let dg = Catalog.groups.first { $0.liab }!
        out.append(Item(id: "g:debt", name: dg.name, value: sp.debts, color: dg.color, grad: "debt", liab: true, group: "debt"))
        return out.filter { $0.value > 0 }.sorted { $0.value > $1.value }.ordered(by: order ?? prefs.bubOrder["top"])
    }

    /// Hold ~0.45s to lift a bubble, then drag it; over another bubble it takes that one's place and the rest slide
    /// into the new order. Releasing saves the order (per level) and the bubble settles into its new spot.
    private func reorder(_ x: Item, items: [Item], P: [Circ]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("bub")))
            .updating($pressing) { v, st, _ in if case .first(true) = v { st = x.id } }
            .onChanged { v in
                guard case .second(true, let g) = v else { return }
                let ids = items.map(\.id)
                guard let i = ids.firstIndex(of: x.id) else { return }
                if drag == nil {
                    withAnimation(.spring(duration: 0.4, bounce: 0.35)) { drag = (x.id, P[i].c, P[i].c) }
                    order = ids
                }
                guard let g, let d = drag else { return }
                let now = CGPoint(x: d.start.x + g.translation.width, y: d.start.y + g.translation.height)
                drag = (d.id, d.start, now)
                // the nearest spot wins (its own included), with a little slack so it doesn't flicker between two
                var hit: Int? = nil, best = hypot(P[i].c.x - now.x, P[i].c.y - now.y) - 12
                for j in P.indices where j != i {
                    let dd = hypot(P[j].c.x - now.x, P[j].c.y - now.y)
                    if dd < best { best = dd; hit = j }
                }
                if let hit {
                    var o = ids; o.remove(at: i); o.insert(x.id, at: hit)
                    withAnimation(.spring(duration: 0.45, bounce: 0.2)) { order = o }
                }
            }
            .onEnded { _ in
                if let o = order { prefs.bubOrder[level ?? "top"] = o }
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) { drag = nil; order = nil }
            }
    }

    private func tap(_ x: Item, at c: CGPoint) {
        if let a = x.account { onOpen(a); return }
        guard let gk = x.group else { return }
        origin = c; cameBack = nil
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) { level = gk }
    }
    private func back() {
        cameBack = level; origin = nil
        withAnimation(.spring(duration: 0.5, bounce: 0.15)) { level = nil }
    }

    /// Where a bubble grows from: inside a group, the opened group's spot; coming back, its own spot.
    private func start(for x: Item, i: Int, P: [Circ], size: CGSize) -> CGPoint {
        if level != nil, let o = origin { return o }
        return P[i].c
    }

    // MARK: header + legend

    @ViewBuilder private func header(_ items: [Item]) -> some View {
        if let level, let g = Catalog.groups.first(where: { $0.id == level }) {
            let net = items.reduce(0) { $0 + ($1.liab ? -$1.value : $1.value) }
            HStack {
                Button(action: back) {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)); Text(g.name).font(.system(size: 15, weight: .semibold)) }
                }
                .buttonStyle(.plain)
                Spacer()
                Text((net < 0 ? "−" : "") + Money.format(abs(net), store.data.base, decimals: 0))
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit().masked()
            }
        } else {
            Text("Tap to open").font(.system(size: 13)).foregroundStyle(Color.sec).frame(maxWidth: .infinity)
        }
    }

    private func legend(_ items: [Item]) -> some View {
        let assets = max(1, items.filter { !$0.liab }.reduce(0) { $0 + $1.value })
        let nAssets = items.filter { !$0.liab }.count
        let sorted = items.sorted { ($0.liab ? 1 : 0, -$0.value) < ($1.liab ? 1 : 0, -$1.value) }
        return VStack(spacing: 0) {
            ForEach(sorted) { x in
                Button { if let a = x.account { onOpen(a) } else if x.group != nil { tap(x, at: CGPoint(x: 160, y: 150)) } } label: {
                    HStack(spacing: 10) {
                        Circle().fill(Catalog.gradient(x.grad)).frame(width: 10, height: 10)
                        Text(x.equity ? "Property equity" : x.name).font(.system(size: 15)).lineLimit(1)
                        Spacer()
                        if !x.liab && !(level != nil && nAssets < 2) {
                            let p = x.value / assets * 100
                            Text(p < 1 ? "<1%" : "\(Int(p.rounded()))%").font(.system(size: 13)).foregroundStyle(Color.sec).monospacedDigit()
                        }
                        Text((x.liab ? "−" : "") + Money.format(x.value, store.data.base, decimals: 0))
                            .font(.system(size: 15, weight: .medium)).monospacedDigit().frame(minWidth: 80, alignment: .trailing).masked()
                    }
                    .padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if items.contains(where: \.liab), items.contains(where: { !$0.liab }) {
                let t = items.reduce(0) { $0 + ($1.liab ? -$1.value : $1.value) }
                Divider().padding(.vertical, 4)
                HStack {
                    Text(level != nil ? "Your equity" : "Net worth").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text((t < 0 ? "−" : "") + Money.format(abs(t), store.data.base, decimals: 0)).font(.system(size: 15, weight: .semibold)).monospacedDigit().masked()
                }
                .padding(.vertical, 6)
            }
            if let level, let g = Catalog.groups.first(where: { $0.id == level }) {
                Button { onAdd(g.types[0]) } label: {
                    Label("Add to \(g.name)", systemImage: "plus").font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .id(level ?? "top")
        .transition(.opacity)
    }

    // MARK: layout (ported from the web app's topLayout / packCircles / hexLayout)

    struct Circ { var c: CGPoint; var r: CGFloat }
    static let maxD: CGFloat = 150, groupMinR: CGFloat = 44, hexFitMin: CGFloat = 76, gapMax: CGFloat = 18
    static func gap(_ d: CGFloat) -> CGFloat { max(6, min(gapMax, d * 0.12)) }

    /// Packing is a few hundred relaxation steps, so a layout is computed once per (level, size, order, values) and
    /// reused: re-renders during animations, drags and scrolling cost nothing.
    @MainActor private static var cache: [String: [Circ]] = [:]
    private func layout(_ items: [Item], size: CGSize) -> [Circ] {
        guard size.width > 0, !items.isEmpty else { return items.map { _ in Circ(c: .zero, r: 0) } }
        let key = "\(level ?? "top")|\(Int(size.width))x\(Int(size.height))|" + items.map { "\($0.id)=\(Int($0.value))" }.joined(separator: ",")
        if let hit = Self.cache[key] { return hit }
        let P = level == nil ? Self.arrange(items.map(\.value), size) : Self.hex(items.count, size)
        if Self.cache.count > 60 { Self.cache.removeAll() }
        Self.cache[key] = P
        return P
    }

    /// Groups: area true to value (at least 44pt radius so name and total fit, at most 150pt across), the biggest in
    /// the middle and the rest spiralling round it, scaled down until all fit with gaps.
    static func top(_ vals: [Double], _ s: CGSize) -> [Circ] {
        let W = s.width, H = s.height, sum = max(1, vals.reduce(0, +)), vmax = max(1, vals.max() ?? 1)
        var k = min(sqrt(W * H * 0.5 / (.pi * sum)), min(W, H) * 0.42 / sqrt(vmax))
        var P: [Circ] = []
        for _ in 0..<30 {
            P = pack(vals.map { min(maxD / 2, max(groupMinR, k * sqrt($0))) }, s)
            if fits(P, s) { break }
            k *= 0.94
        }
        return P
    }
    /// Fixed spots for groups: the default layout (biggest first) defines where the spots are; a custom order puts each
    /// group on the spot for its position, keeping its own size, and the cluster relaxes so nothing overlaps.
    /// Same order in, same layout out.
    static func arrange(_ vals: [Double], _ s: CGSize) -> [Circ] {
        let byValue = vals.indices.sorted { vals[$0] > vals[$1] }
        let base = top(byValue.map { vals[$0] }, s)
        var r = Array(repeating: CGFloat(0), count: vals.count)
        for (k, idx) in byValue.enumerated() { r[idx] = base[k].r }
        if byValue == Array(vals.indices) { return base }
        var sc: CGFloat = 1, P: [Circ] = []
        for _ in 0..<20 {
            P = pack(r.map { $0 * sc }, s, start: base.map(\.c), its: 300)
            if fits(P, s) { break }
            sc *= 0.96
        }
        return P
    }
    static func fits(_ P: [Circ], _ s: CGSize) -> Bool {
        for i in P.indices {
            let a = P[i]
            if a.c.x - a.r < 1 || a.c.y - a.r < 1 || a.c.x + a.r > s.width - 1 || a.c.y + a.r > s.height - 1 { return false }
            for j in P.indices where j > i {
                let b = P[j]
                if hypot(a.c.x - b.c.x, a.c.y - b.c.y) < a.r + b.r + gap(2 * min(a.r, b.r)) { return false }
            }
        }
        return true
    }
    static func pack(_ rs: [CGFloat], _ s: CGSize, start: [CGPoint]? = nil, its: Int = 360) -> [Circ] {
        let cx = s.width / 2, cy = s.height / 2
        var P = rs.enumerated().map { i, r -> Circ in
            if let start, start.indices.contains(i) { return Circ(c: start[i], r: r) }
            let a = Double(i) * 2.39996, d = i > 0 ? 18 * sqrt(Double(i)) : 0
            return Circ(c: CGPoint(x: cx + cos(a) * d, y: cy + sin(a) * d), r: r)
        }
        for it in 0..<its {
            let pull = start != nil ? 0.0012 : 0.035 * (1 - Double(it) / Double(its)) + 0.004
            for i in P.indices { P[i].c.x += (cx - P[i].c.x) * pull; P[i].c.y += (cy - P[i].c.y) * pull }
            for i in P.indices { for j in P.indices where j > i {
                let dx = P[j].c.x - P[i].c.x, dy = P[j].c.y - P[i].c.y, d = max(0.01, hypot(dx, dy))
                let mn = P[i].r + P[j].r + gap(2 * min(P[i].r, P[j].r)) + 1
                if d < mn {
                    let push = (mn - d) / 2, ux = dx / d, uy = dy / d
                    let wa = P[j].r / (P[i].r + P[j].r), wb = P[i].r / (P[i].r + P[j].r)
                    P[i].c.x -= ux * push * 2 * wa; P[i].c.y -= uy * push * 2 * wa
                    P[j].c.x += ux * push * 2 * wb; P[j].c.y += uy * push * 2 * wb
                }
            } }
            for i in P.indices {
                P[i].c.x = min(s.width - P[i].r - 2, max(P[i].r + 2, P[i].c.x))
                P[i].c.y = min(s.height - P[i].r - 2, max(P[i].r + 2, P[i].c.y))
            }
        }
        return P
    }
    /// Entries in a group: all the same size, sharing the box on a honeycomb (one fills it, two split it, …).
    static func hex(_ n: Int, _ s: CGSize) -> [Circ] {
        let W = s.width, H = s.height, pad = gapMax, s3 = sqrt(3) / 2
        var best: (c: Int, rows: Int, cell: CGFloat)? = nil
        for c in 1...n {
            let rows = Int(ceil(Double(n) / Double(c))), off: CGFloat = rows > 1 ? 0.5 : 0
            let cell = min((W - pad) / (CGFloat(c) + off), (H - pad) / (1 + CGFloat(rows - 1) * s3), maxD + gapMax)
            if best == nil || cell > best!.cell + 0.5 || (abs(cell - best!.cell) <= 0.5 && rows < best!.rows) { best = (c, rows, cell) }
        }
        let (c, rows) = (best!.c, best!.rows)
        let cell = max(48, min(best!.cell, min(W, H) - pad, maxD + gapMax))
        return (0..<n).map { i in
            let row = i / c, m = row == rows - 1 ? n - row * c : c
            let shift: CGFloat = rows > 1 ? (row % 2 == 1 ? cell / 4 : -cell / 4) : 0
            let col = (i - row * c) + Int(((Double(c - m)) / 2 + (m < c && row % 2 == 1 ? -0.01 : 0.01)).rounded())
            let hx = (CGFloat(col) - CGFloat(c - 1) / 2) * cell + shift, hy = (CGFloat(row) - CGFloat(rows - 1) / 2) * cell * s3
            return Circ(c: CGPoint(x: W / 2 + hx, y: H / 2 + hy), r: (cell - gap(cell)) / 2)
        }
    }
}

/// One bubble: a two-colour gradient with a soft highlight, name and amount; it grows out of `from` to its spot.
private struct Bubble: View {
    @Environment(Store.self) private var store
    let item: Bubbles.Item
    let r: CGFloat
    let at: CGPoint
    let from: CGPoint
    let delay: Double
    var dragAt: CGPoint? = nil      // lifted and following the finger
    var pressing = false            // held, about to lift
    @State private var shown = false
    @State private var floatY: CGFloat = 0

    var body: some View {
        let d = r * 2
        ZStack {
            Circle().fill(Catalog.gradient(item.grad))
            Circle().fill(RadialGradient(colors: [.white.opacity(0.3), .clear], center: UnitPoint(x: 0.32, y: 0.24), startRadius: 0, endRadius: r * 1.1))
            VStack(spacing: 1) {
                if let s = item.symbol, d >= 96 { Image(systemName: s).font(.system(size: 16, weight: .semibold)).padding(.bottom, 2) }
                if true {
                    Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                }
                Text((item.liab ? "−" : "") + Money.format(item.value, store.data.base, decimals: 0))
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).masked()
            }
            .foregroundStyle(.white).shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .padding(.horizontal, d * 0.12)
            .opacity(shown ? 1 : 0)
        }
        .frame(width: d, height: d)
        .compositingGroup()
        .shadow(color: .black.opacity(dragAt != nil ? 0.6 : 0.3), radius: dragAt != nil ? 22 : 8, y: dragAt != nil ? 16 : 5)
        .scaleEffect(dragAt != nil ? 1.14 : pressing ? 0.9 : 1)
        .animation(pressing ? .timingCurve(0.3, 0, 0.2, 1, duration: 0.55) : .spring(duration: 0.45, bounce: 0.4), value: pressing)
        .scaleEffect(shown ? 1 : 0.05)
        .opacity(shown ? 1 : 0)
        .offset(y: dragAt == nil ? floatY : 0)
        .position(dragAt ?? (shown ? at : from))
        .animation(dragAt == nil ? .spring(duration: 0.55, bounce: 0.22) : nil, value: at)
        .animation(.spring(duration: 0.55, bounce: 0.22), value: r)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.25).delay(delay)) { shown = true }
            withAnimation(.easeInOut(duration: 4 + Double(item.id.count % 5) * 0.6).repeatForever(autoreverses: true).delay(delay + 0.8)) { floatY = -3 }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private extension Array where Element == Bubbles.Item {
    /// Keep an arranged order: saved ids first in their order, anything new after them, biggest first.
    func ordered(by saved: [String]?) -> [Element] {
        guard let saved, !saved.isEmpty else { return self }
        let pos = Dictionary(saved.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return enumerated().sorted { (pos[$0.element.id] ?? 1_000_000 + $0.offset) < (pos[$1.element.id] ?? 1_000_000 + $1.offset) }.map(\.element)
    }
}
