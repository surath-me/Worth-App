import SwiftUI

/// First run (and after Erase all data): one question per screen. Intro (the logo with its bubbles) → main currency →
/// what you own → what you owe → one balance at a time on an in-app keypad → "You're good to go!".
struct Onboarding: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onPastMonths: () -> Void = {}

    enum Step: Int { case intro, currency, own, owe, bal, done }
    struct Row: Equatable { var t: String; var name: String; var cur: String; var raw: String = "" }

    @State private var step: Step = .intro
    @State private var forward = true
    @State private var cur = "EUR"
    @State private var own: [String] = []
    @State private var owe: [String] = []
    @State private var rows: [Row] = []
    @State private var i = 0
    @State private var zoom = false          // the intro's logo is filling the screen
    @State private var showGreen = false     // the green from the zoom, fading over the next screen

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Color.hex(0x36F5B2).opacity(0.22), .clear], center: UnitPoint(x: 0.25, y: 0), startRadius: 0, endRadius: 380).ignoresSafeArea()
            RadialGradient(colors: [Color.hex(0x3AA4FF).opacity(0.2), .clear], center: UnitPoint(x: 0.9, y: 0.05), startRadius: 0, endRadius: 340).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar.opacity(step == .intro || zoom ? 0 : 1)
                ZStack { page.id("\(step.rawValue)-\(i)").transition(pageTransition) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if showGreen {
                LinearGradient(colors: [.hex(0x34D69E), .hex(0x11A27C), .hex(0x0B7F68)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea().transition(.opacity).allowsHitTesting(false)
            }
        }
        .onAppear { cur = store.data.base }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(x: forward ? 44 : -44)),
                    removal: .opacity.combined(with: .offset(x: forward ? -36 : 36)))
    }

    private func go(_ s: Step, back: Bool = false) {
        forward = !back
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5)) { step = s }
    }

    // MARK: top bar: back · progress · skip

    private var topBar: some View {
        HStack {
            Button {
                if step == .bal && i > 0 { forward = false; withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5)) { i -= 1 } }
                else if let s = Step(rawValue: step.rawValue - 1) { go(s, back: true) }
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.1)))
            }
            .opacity(step == .done ? 0 : 1)
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...4, id: \.self) { k in
                    Capsule().fill(k == step.rawValue ? Color.g1 : k < step.rawValue ? Color.white.opacity(0.5) : Color.white.opacity(0.18))
                        .frame(width: k == step.rawValue ? 26 : 7, height: 7)
                }
            }
            .opacity(step == .done ? 0 : 1)
            .animation(.spring(duration: 0.5, bounce: 0.2), value: step)
            Spacer()
            Button("Skip") { owe = []; buildRows(); i = 0; go(.bal) }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(width: 44)
                .opacity(step == .owe ? 1 : 0).disabled(step != .owe)
        }
        .padding(.horizontal, 20).padding(.top, 6).frame(height: 56)
    }

    // MARK: pages

    @ViewBuilder private var page: some View {
        switch step {
        case .intro: intro
        case .currency: currencyPage
        case .own: pickPage(title: "What do you own?", liab: false)
        case .owe: pickPage(title: "Anything you owe?", liab: true)
        case .bal: BalancePage(row: $rows[i], index: i, count: rows.count, next: nextBalance, addAnother: addAnother)
        case .done: donePage
        }
    }

    private var intro: some View {
        IntroPage(zoom: $zoom) {
            // the zoom has covered the screen: swap in the next screen underneath and let the green fade away
            showGreen = true; zoom = false
            forward = true; step = .currency
            withAnimation(.easeOut(duration: 0.45).delay(0.05)) { showGreen = false }
        } restore: { data in
            do { try store.restore(data); dismiss() } catch {}
        }
    }

    private var currencyPage: some View {
        PageScaffold(title: "Your main currency", sub: "Totals show in this.") {
            VStack(spacing: 10) {
                ForEach(Currency.all, id: \.self) { c in
                    OptionCard(selected: c == cur) { cur = c } label: {
                        Text(Currency.symbol[c] ?? c).font(.system(size: 17, weight: .bold)).frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Currency.name[c] ?? c).font(.system(size: 15, weight: .semibold))
                            Text(c).font(.system(size: 12)).foregroundStyle(Color.sec)
                        }
                    }
                }
            }
        } foot: {
            Button("Continue") { for k in rows.indices where rows[k].raw.isEmpty { rows[k].cur = cur }; go(.own) }.buttonStyle(PrimaryButton())
        }
    }

    private func pickPage(title: String, liab: Bool) -> some View {
        let kinds = Catalog.kinds.filter { Catalog.isLiab($0.t) == liab }
        let picked = liab ? owe : own
        return PageScaffold(title: title, sub: "Pick all that apply.") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(kinds, id: \.t) { k in
                    let on = picked.contains(k.t), t = Catalog.type(k.t)
                    Button {
                        if liab { owe = on ? owe.filter { $0 != k.t } : owe + [k.t] } else { own = on ? own.filter { $0 != k.t } : own + [k.t] }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Avatar(symbol: Catalog.safeSymbol(t.symbol), color: t.color, size: 38, grad: t.id)
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                                    .foregroundStyle(on ? Color.g1 : Color.white.opacity(0.25)).symbolEffect(.bounce, value: on)
                            }
                            Text(k.n).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        .padding(14).frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(on ? Color.g1 : .clear, lineWidth: 2))
                        .scaleEffect(on ? 0.98 : 1).animation(.spring(duration: 0.3, bounce: 0.4), value: on)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: on)
                }
            }
        } foot: {
            if liab {
                Button(owe.isEmpty ? "I owe nothing" : "Continue") { buildRows(); i = 0; go(.bal) }.buttonStyle(PrimaryButton())
            } else {
                Button("Continue") { go(.owe) }.buttonStyle(PrimaryButton()).disabled(own.isEmpty)
            }
        }
    }

    private var donePage: some View {
        VStack(spacing: 0) {
            LogoArt(entryDelay: 0.1, exiting: false).frame(height: 330).padding(.top, 10)
            Spacer(minLength: 10)
            VStack(spacing: 8) {
                Text("You’re good to go!").font(.system(size: 30, weight: .bold))
                Text(Money.format(store.liveTotal, store.data.base, decimals: 0)).font(.system(size: 38, weight: .bold)).monospacedDigit()
                Text("Your net worth today").font(.system(size: 15)).foregroundStyle(Color.sec)
            }
            .appear(delay: 0.9)
            Spacer(minLength: 10)
            VStack(spacing: 6) {
                Button("Continue") { dismiss() }.buttonStyle(PrimaryButton())
                Button("Add past months") { dismiss(); onPastMonths() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(height: 44)
            }
            .appear(delay: 1.1)
        }
        .padding(.horizontal, 20).padding(.bottom, 8)
    }

    // MARK: balances

    private func buildRows() {
        let want = own + owe
        var keep = rows.filter { want.contains($0.t) }
        for t in want where !keep.contains(where: { $0.t == t }) { keep.append(Row(t: t, name: Catalog.kinds.first { $0.t == t }!.n, cur: cur)) }
        rows = keep.sorted { want.firstIndex(of: $0.t)! < want.firstIndex(of: $1.t)! }
        i = min(i, max(0, rows.count - 1))
    }
    private func nextBalance() {
        if i == rows.count - 1 { finish() }
        else { forward = true; withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5)) { i += 1 } }
    }
    private func addAnother() {
        let r = rows[i], same = rows.filter { $0.t == r.t }.count
        rows.insert(Row(t: r.t, name: "\(Catalog.kinds.first { $0.t == r.t }!.n) \(same + 1)", cur: r.cur), at: i + 1)
        forward = true; withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5)) { i += 1 }
    }
    private func finish() {
        let entries = rows.compactMap { r -> Account? in
            guard let v = Double(r.raw) else { return nil }
            let name = r.name.trimmingCharacters(in: .whitespaces)
            return Account(name: name.isEmpty ? Catalog.kinds.first { $0.t == r.t }!.n : name, type: r.t, cur: r.cur, bal: abs(v))
        }
        store.finishSetup(base: cur, entries: entries)
        go(.done)
    }
}

// MARK: - shared page layout

private struct PageScaffold<Content: View, Foot: View>: View {
    let title: String
    let sub: String
    @ViewBuilder let content: Content
    @ViewBuilder let foot: Foot

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 30, weight: .bold)).padding(.top, 6).appear(delay: 0.12)
                    Text(sub).font(.system(size: 15)).foregroundStyle(Color.sec).padding(.top, 6).padding(.bottom, 20).appear(delay: 0.18)
                    content.appear(delay: 0.24)
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            foot.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8).appear(delay: 0.32)
        }
    }
}

private struct OptionCard<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: Label
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                label
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                    .foregroundStyle(selected ? Color.g1 : Color.white.opacity(0.25))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? Color.g1 : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

extension View {
    /// Slide in from the right and fade, after `delay` (a page's parts arrive one after another).
    func appear(delay: Double) -> some View { modifier(Appear(delay: delay)) }
}
private struct Appear: ViewModifier {
    let delay: Double
    @State private var on = false
    func body(content: Content) -> some View {
        content.opacity(on ? 1 : 0).offset(x: on ? 0 : 30)
            .onAppear { withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.56).delay(delay)) { on = true } }
    }
}

// MARK: - intro

/// "Watch your worth grow." The logo comes into focus, its bubbles slide out from behind it, ripples keep breathing.
/// "Get started" (only once everything has landed) pulls the bubbles back in on an anticlockwise spiral, the logo
/// swallows them and zooms until its green fills the screen.
private struct IntroPage: View {
    @Binding var zoom: Bool
    let done: () -> Void
    let restore: (Data) -> Void
    @State private var exiting = false
    @State private var ready = false
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            LogoArt(entryDelay: 0, exiting: exiting, onReady: { ready = true }, onZoomed: done).frame(height: 360).padding(.top, 30)
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                Text("Watch your worth grow.").font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center)
                Text("Every account, home and loan.\nIn any currency.").font(.system(size: 15)).foregroundStyle(Color.sec).multilineTextAlignment(.center)
            }
            .appear(delay: 0.65)
            .opacity(exiting ? 0 : 1).offset(y: exiting ? 10 : 0).animation(.easeIn(duration: 0.2), value: exiting)
            Spacer(minLength: 8)
            VStack(spacing: 6) {
                Button("Get started") { guard ready, !exiting else { return }; exiting = true; zoom = true }.buttonStyle(PrimaryButton())
                Button("Restore a backup") { importing = true }.font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(height: 44)
            }
            .modifier(SlowAppear())
            .opacity(exiting ? 0 : 1).animation(.easeIn(duration: 0.2), value: exiting)
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { r in
            guard case .success(let url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url) { restore(d) }
        }
    }
}
/// The intro's buttons start midway through the entry, slowly.
private struct SlowAppear: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content.opacity(on ? 1 : 0).offset(y: on ? 0 : 16)
            .onAppear { withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.3).delay(1.15)) { on = true } }
    }
}

/// The logo in its green circle with two breathing ripples and the category bubbles around it.
struct LogoArt: View {
    let entryDelay: Double
    let exiting: Bool
    var onReady: () -> Void = {}
    var onZoomed: () -> Void = {}

    // icon, gradient key, size, position (% of the box)
    static let sats: [(k: String?, g: String, s: CGFloat, x: CGFloat, y: CGFloat)] = [
        ("property", "property", 96, 0.82, 0.15), ("bank", "savings", 70, 0.15, 0.21), ("etf", "inv", 60, 0.24, 0.86),
        ("vehicle", "more", 48, 0.90, 0.61), ("crypto", "crypto", 38, 0.11, 0.57), ("cash", "cash", 32, 0.71, 0.91),
        (nil, "mf", 18, 0.54, 0.04), (nil, "etf", 13, 0.46, 0.97),
    ]
    @State private var coreIn = false
    @State private var out: [Bool] = Array(repeating: false, count: 8)
    @State private var pull: [CGFloat] = Array(repeating: 0, count: 8)
    @State private var coreScale: CGFloat = 1
    @State private var curveGone = false

    var body: some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            ZStack {
                if !exiting {
                    Ripple(delay: entryDelay + 0.5); Ripple(delay: entryDelay + 2.5)
                }
                ForEach(Array(Self.sats.enumerated()), id: \.offset) { k, b in
                    let p = CGPoint(x: g.size.width * b.x, y: g.size.height * b.y)
                    SatBubble(sat: b)
                        .modifier(Spiral(t: pull[k], from: p, to: c))
                        .scaleEffect(out[k] ? 1 : 0.3)
                        .position(out[k] ? p : CGPoint(x: c.x + (p.x - c.x) * 0.2, y: c.y + (p.y - c.y) * 0.2))
                        .opacity(out[k] ? (pull[k] >= 1 ? 0 : 1) : 0)
                }
                ZStack {
                    Circle().fill(LinearGradient(colors: [.hex(0x34D69E), .hex(0x11A27C), .hex(0x0B7F68)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: Color.hex(0x34D69E).opacity(0.35), radius: 24)
                    DrawnLogo(lineWidth: 9, delay: entryDelay + 0.55).frame(width: 96, height: 96).opacity(curveGone ? 0 : 1)
                }
                .frame(width: 156, height: 156)
                .scaleEffect(coreIn ? coreScale : 0.6)
                .blur(radius: coreIn ? 0 : 14)
                .opacity(coreIn ? 1 : 0)
                .position(c)
                .zIndex(5)
            }
            .onChange(of: exiting) { _, on in
                if on {
                    let f = g.frame(in: .global), sc = UIScreen.main.bounds
                    exit(center: CGPoint(x: f.minX + c.x, y: f.minY + c.y), screen: sc.size)
                }
            }
        }
        .onAppear(perform: enter)
    }

    private func enter() {
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.1).delay(entryDelay)) { coreIn = true }
        let order = Self.sats.indices.sorted { Self.sats[$0].s > Self.sats[$1].s } // biggest first
        for (n, k) in order.enumerated() {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.5).delay(entryDelay + 0.48 + Double(n) * 0.08)) { out[k] = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + entryDelay + 0.48 + Double(order.count) * 0.08 + 1.5) { onReady() }
    }

    private func exit(center c: CGPoint, screen: CGSize) {
        let order = Self.sats.indices.sorted { Self.sats[$0].s < Self.sats[$1].s } // smallest first
        for (n, k) in order.enumerated() {
            withAnimation(.timingCurve(0.6, 0, 0.9, 0.4, duration: 0.44).delay(Double(n) * 0.018)) { pull[k] = 1 }
        }
        withAnimation(.easeIn(duration: 0.3).delay(0.06)) { curveGone = true }
        // the logo draws in (~85%) as it swallows the last bubbles, then grows faster and faster until it fills the screen
        let t = 0.09 + Double(order.count) * 0.01
        // big enough that the circle covers the whole screen from wherever the logo sits
        let far = [CGPoint.zero, CGPoint(x: screen.width, y: 0), CGPoint(x: 0, y: screen.height), CGPoint(x: screen.width, y: screen.height)]
            .map { hypot($0.x - c.x, $0.y - c.y) }.max() ?? 900
        let k = far / 78 * 1.08
        withAnimation(.timingCurve(0.3, 0, 0.3, 1, duration: 0.375).delay(t)) { coreScale = 0.85 }
        withAnimation(.timingCurve(0.75, 0, 0.95, 0.45, duration: 0.6).delay(t + 0.375)) { coreScale = k }
        DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.375 + 0.6) { onZoomed() }
    }
}

/// A bubble pulled into the logo along an anticlockwise spiral: the radius shrinks and the angle turns back ~55°.
private struct Spiral: GeometryEffect {
    var t: CGFloat
    let from: CGPoint
    let to: CGPoint
    var animatableData: CGFloat { get { t } set { t = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        guard t > 0 else { return ProjectionTransform(.identity) }
        let ox = from.x - to.x, oy = from.y - to.y, r0 = hypot(ox, oy), a0 = atan2(oy, ox)
        let r = r0 * (1 - t), a = a0 - 0.95 * t
        let dx = to.x + r * cos(a) - from.x, dy = to.y + r * sin(a) - from.y
        let s = 1 - 0.7 * t, w = size.width / 2, h = size.height / 2
        // shrink about its own centre, then move along the spiral
        return ProjectionTransform(CGAffineTransform(translationX: -w, y: -h)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: w + dx, y: h + dy)))
    }
}

private struct SatBubble: View {
    let sat: (k: String?, g: String, s: CGFloat, x: CGFloat, y: CGFloat)
    @State private var drift = false
    var body: some View {
        ZStack {
            Circle().fill(Catalog.gradient(sat.g))
            Circle().fill(RadialGradient(colors: [.white.opacity(0.3), .clear], center: UnitPoint(x: 0.32, y: 0.24), startRadius: 0, endRadius: sat.s * 0.55))
            if let k = sat.k { MIcon(Catalog.safeSymbol(Catalog.type(k).symbol), size: sat.s * 0.5).foregroundStyle(.white) }
        }
        .frame(width: sat.s, height: sat.s)
        .offset(x: drift ? max(3, 9 - sat.s / 14) * 0.5 : 0, y: drift ? -max(3, 9 - sat.s / 14) : 0)
        .onAppear { withAnimation(.easeInOut(duration: 4.5 + Double(Int(sat.s) % 5) * 0.7).repeatForever(autoreverses: true)) { drift = true } }
    }
}

/// A soft green ring breathing out of the logo, on a loop.
private struct Ripple: View {
    let delay: Double
    @State private var p: CGFloat = 0
    var body: some View {
        Circle().stroke(Color.hex(0x34D69E).opacity(0.55), lineWidth: 1.5)
            .frame(width: 156, height: 156)
            .modifier(RippleEffect(p: p))
            .onAppear { withAnimation(.timingCurve(0.25, 0.5, 0.4, 1, duration: 4).delay(delay).repeatForever(autoreverses: false)) { p = 1 } }
    }
}
private struct RippleEffect: ViewModifier, Animatable {
    var p: CGFloat
    var animatableData: CGFloat { get { p } set { p = newValue } }
    func body(content: Content) -> some View {
        let scale = p < 0.2 ? 0.96 + (1.13 - 0.96) * p / 0.2 : 1.13 + (2.05 - 1.13) * (p - 0.2) / 0.8
        let op = p == 0 ? 0 : p < 0.2 ? 0.36 * p / 0.2 : 0.36 * (1 - (p - 0.2) / 0.8)
        return content.scaleEffect(scale).opacity(op)
    }
}

// MARK: - one balance

/// One entry per screen: icon and editable name, the question, a big amount typed on the app's own keypad (so the
/// system keyboard never pushes the layout around), a currency pill that opens a tray, Next / Finish, "Add another".
private struct BalancePage: View {
    @Binding var row: Onboarding.Row
    let index: Int
    let count: Int
    let next: () -> Void
    let addAnother: () -> Void
    @FocusState private var nameFocused: Bool
    @State private var tray = false
    @State private var blink = false

    var body: some View {
        let t = Catalog.type(row.t)
        VStack(spacing: 0) {
            Text("\(index + 1) of \(count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sec)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10).appear(delay: 0.12)
            HStack(spacing: 12) {
                Avatar(symbol: Catalog.safeSymbol(t.symbol), color: t.color, size: 52, grad: t.id)
                TextField("Name", text: $row.name).font(.system(size: 22, weight: .bold)).focused($nameFocused).submitLabel(.done)
                    .tint(Color.hex(0x3CD9CF))
                Button { nameFocused = true } label: {
                    Image(systemName: "pencil").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.1)))
                }
                .accessibilityLabel("Rename")
            }
            .padding(.top, 10).appear(delay: 0.16)
            Text(Catalog.ask(row.t) + " Rough is fine.").font(.system(size: 15)).foregroundStyle(Color.sec)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8).appear(delay: 0.2)
            Spacer(minLength: 4)
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Currency.symbol[row.cur] ?? row.cur).font(.system(size: size * 0.55, weight: .bold)).foregroundStyle(Color.sec)
                    Text(display.isEmpty ? "0" : display).font(.system(size: size, weight: .bold)).monospacedDigit()
                        .foregroundStyle(display.isEmpty ? Color.white.opacity(0.3) : .white)
                        .contentTransition(.numericText()).animation(.snappy(duration: 0.18), value: display)
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.hex(0x3CD9CF)).frame(width: 3, height: size * 0.82)
                        .opacity(nameFocused ? 0 : blink ? 1 : 0)
                }
                .lineLimit(1).minimumScaleFactor(0.5)
                Button { tray = true } label: {
                    HStack(spacing: 4) { Text(row.cur); Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)) }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 34).background(Capsule().fill(Color(.secondarySystemBackground)))
                }
                .accessibilityLabel("Currency \(row.cur)")
            }
            .appear(delay: 0.24)
            Spacer(minLength: 4)
            Keypad { press($0) } clear: { row.raw = "" }.appear(delay: 0.28)
            VStack(spacing: 4) {
                Button(index == count - 1 ? "Finish" : "Next") { nameFocused = false; next() }.buttonStyle(PrimaryButton()).disabled(Double(row.raw) == nil)
                Button { addAnother() } label: { Label("Add another", systemImage: "plus") }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(height: 40)
            }
            .padding(.top, 10).appear(delay: 0.32)
        }
        .padding(.horizontal, 20).padding(.bottom, 8)
        .onAppear { withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { blink = true } }
        .sheet(isPresented: $tray) { CurrencyTray(cur: $row.cur) }
    }

    private var size: CGFloat { display.count > 13 ? 34 : display.count > 10 ? 42 : display.count > 7 ? 50 : 58 }

    /// The whole part grouped the way that currency writes it (₹6,31,394), one decimal point, two decimals max.
    private var display: String {
        let raw = row.raw
        guard !raw.isEmpty else { return "" }
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        f.locale = Locale(identifier: Currency.locale[row.cur] ?? "en_IE")
        let int = f.string(from: NSNumber(value: Double(parts[0]) ?? 0)) ?? String(parts[0])
        return parts.count > 1 ? int + (f.decimalSeparator ?? ".") + parts[1] : int
    }

    private func press(_ k: String) {
        var r = row.raw
        if k == "del" { r = String(r.dropLast()) }
        else if k == "." { if !r.contains(".") { r = (r.isEmpty ? "0" : r) + "." } }
        else {
            if let d = r.firstIndex(of: "."), r.distance(from: d, to: r.endIndex) > 2 { return }
            if !r.contains("."), r.drop(while: { $0 == "0" }).count >= 12 { return }
            r = r == "0" ? k : r + k
        }
        row.raw = r
    }
}

/// Digits, a decimal point and backspace (hold it to clear), with a light tap on each press.
private struct Keypad: View {
    let press: (String) -> Void
    let clear: () -> Void
    @State private var taps = 0
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 2) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "del"], id: \.self) { k in
                Button { press(k); taps += 1 } label: {
                    Group {
                        if k == "del" { Image(systemName: "delete.left").font(.system(size: 22, weight: .medium)) }
                        else { Text(k).font(.system(size: 28, weight: .medium)) }
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 54).contentShape(Rectangle())
                }
                .buttonStyle(KeyStyle())
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in if k == "del" { clear(); taps += 1 } })
                .accessibilityLabel(k == "del" ? "Delete" : k == "." ? "Decimal point" : k)
            }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: taps)
    }
}
private struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// The currency tray: iOS's own drawer (its background and grabber) holding the same selection cards as the
/// "Your main currency" page, with a left-aligned title like the onboarding pages. The drawer is exactly as tall as its
/// content. Tap one to pick it (it closes a beat later); drag down or tap outside to close.
private struct CurrencyTray: View {
    @Binding var cur: String
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 430

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Currency").font(.system(size: 22, weight: .bold)).padding(.horizontal, 4)
            VStack(spacing: 10) {
                ForEach(Currency.all, id: \.self) { c in
                    OptionCard(selected: c == cur) {
                        cur = c
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { dismiss() }
                    } label: {
                        Text(Currency.symbol[c] ?? c).font(.system(size: 17, weight: .bold)).frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Currency.name[c] ?? c).font(.system(size: 15, weight: .semibold))
                            Text(c).font(.system(size: 12)).foregroundStyle(Color.sec)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
    }
}
