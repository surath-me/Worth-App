import SwiftUI
import Charts

/// The main tab: net worth (tap it to hide amounts), the change over the chosen range, one plain-language insight,
/// the curve (press and drag along it to read any month), the "Add past months" card, and the bubbles.
struct NetWorthView: View {
    @Environment(Store.self) private var store
    @Environment(Prefs.self) private var prefs
    @State private var editing: Account?
    @State private var adding: String?          // a type to start a new entry with
    @State private var checkIn: String?         // a month to open the check-in for
    @State private var scrub: Store.Point?      // the month being read on the chart

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle("Net worth")
                if store.isEmpty { EmptyState() } else {
                    hero
                    WorthChart(scrub: $scrub).padding(.top, 12)
                    RangePicker().padding(.top, 14)
                    BackfillCard { checkIn = $0 }.padding(.top, 16)
                    if store.data.accounts.contains(where: { store.conv($0.bal, $0.cur) > 0 }) {
                        SectionTitle("Breakdown")
                        Bubbles(onOpen: { editing = $0 }, onAdd: { adding = $0 })
                    }
                    SavedFoot()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDisabled(scrub != nil)
        .background(Aura())
        .sheet(item: $editing) { EntrySheet(account: $0) }
        .sheet(item: Binding(get: { adding.map(TypeChoice.init) }, set: { adding = $0?.id })) { EntrySheet(account: nil, startType: $0.id) }
        .sheet(item: Binding(get: { checkIn.map(TypeChoice.init) }, set: { checkIn = $0?.id })) { CheckInSheet(start: $0.id) }
    }

    // MARK: hero

    private var hero: some View {
        let total = scrub?.value ?? store.liveTotal, base = store.data.base
        let pts = store.points(range: prefs.range)
        let ref = pts.first { $0.month != Month.key() }
        return VStack(alignment: .leading, spacing: 2) {
            Text(Money.format(total, base, decimals: 0))
                .font(.system(size: 34, weight: .bold)).kerning(-0.8).monospacedDigit()
                .contentTransition(.numericText(value: total))
                .animation(.snappy(duration: 0.25), value: total)
                .minimumScaleFactor(0.6).lineLimit(1)
                .masked()
                .contentShape(Rectangle())
                .onTapGesture { prefs.hide.toggle() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(prefs.hide ? "Shows amounts" : "Hides amounts")
            delta(total: total, pts: pts, ref: ref).frame(height: 22)
            insight(total: total, ref: ref).frame(minHeight: 18, alignment: .top)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private func delta(total: Double, pts: [Store.Point], ref: Store.Point?) -> some View {
        if let scrub {
            if let first = pts.first, first.month != scrub.month {
                ChangeLabel(change: scrub.value - first.value, from: first.value, cur: store.data.base, suffix: "since " + Month.short(first.month)).masked()
            } else { Text("Start of range").font(.system(size: 15)).foregroundStyle(Color.sec) }
        } else if let ref, let first = pts.first {
            ChangeLabel(change: total - first.value, from: first.value, cur: store.data.base, suffix: store.rangeLabel(ref: ref, range: prefs.range)).masked()
        } else if !store.data.accounts.isEmpty {
            Text("First month").font(.system(size: 15)).foregroundStyle(Color.sec)
        }
    }

    @ViewBuilder private func insight(total: Double, ref: Store.Point?) -> some View {
        let ins = store.insight(total: total, ref: ref)
        if scrub == nil, ins.badge != nil || ins.move != nil {
            (Text(ins.badge ?? "").fontWeight(.semibold).foregroundStyle(.white)
             + Text(ins.badge != nil && ins.move != nil ? " · " : "")
             + Text(ins.move ?? ""))
                .font(.system(size: 13)).foregroundStyle(Color.sec).masked()
                .transition(.opacity)
        }
    }
}

/// Lets a String drive `.sheet(item:)`.
struct TypeChoice: Identifiable { let id: String }

// MARK: - chart

/// The curve, like the web app: a glowing line (green→blue when up over the range, red→orange when down), a soft
/// area under it, a dotted line at the starting value, a glowing dot on the last month, and start/end labels.
/// Press and drag along it to read any month: a label rides above the dot and the hero follows.
struct WorthChart: View {
    @Environment(Store.self) private var store
    @Environment(Prefs.self) private var prefs
    @Binding var scrub: Store.Point?
    @State private var drawn: CGFloat = 0

    var body: some View {
        let pts = store.points(range: prefs.range)
        let up = pts.count < 2 || pts.last!.value >= pts.first!.value
        let c1 = up ? Color.g1 : Color.hex(0xFF4D6A), c2 = up ? Color.hex(0x2F7BEA) : Color.hex(0xFF9F0A)
        let vs = pts.map(\.value)
        let lo0 = vs.min() ?? 0, hi0 = vs.max() ?? 1
        let span = max(hi0 - lo0, max(1, abs(hi0) * 0.04)), lo = lo0 - span * 0.12, hi = hi0 + span * 0.12
        VStack(spacing: 8) {
            if pts.count < 2 {
                Text(pts.isEmpty ? "No data in this range" : "One month so far")
                    .font(.system(size: 13)).foregroundStyle(Color.sec).frame(maxWidth: .infinity, minHeight: 170)
            } else {
                ZStack {
                    // the glow: the same line, blurred, underneath
                    line(pts, lo: lo, hi: hi, c1: c1, c2: c2, width: 6).blur(radius: 6).opacity(0.7)
                    Chart {
                        RuleMark(y: .value("Start", pts[0].value))
                            .foregroundStyle(.white.opacity(0.22)).lineStyle(StrokeStyle(lineWidth: 1, dash: [1.5, 5]))
                        ForEach(pts) { p in
                            AreaMark(x: .value("Month", Month.date(p.month)), yStart: .value("Low", lo), yEnd: .value("Net worth", p.value))
                                .foregroundStyle(LinearGradient(colors: [c2.opacity(0.26), c1.opacity(0.1), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("Month", Month.date(p.month)), y: .value("Net worth", p.value))
                                .foregroundStyle(LinearGradient(colors: [c1, c2], startPoint: .leading, endPoint: .trailing))
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                .interpolationMethod(.monotone)
                        }
                        PointMark(x: .value("Month", Month.date(pts[0].month)), y: .value("Net worth", pts[0].value)).foregroundStyle(c1).symbolSize(36)
                        if let s = scrub {
                            RuleMark(x: .value("Month", Month.date(s.month))).foregroundStyle(.white.opacity(0.3)).lineStyle(StrokeStyle(lineWidth: 1))
                            PointMark(x: .value("Month", Month.date(s.month)), y: .value("Net worth", s.value))
                                .foregroundStyle(c2).symbolSize(150)
                        } else if let last = pts.last {
                            PointMark(x: .value("Month", Month.date(last.month)), y: .value("Net worth", last.value)).foregroundStyle(c2.opacity(0.35)).symbolSize(420)
                            PointMark(x: .value("Month", Month.date(last.month)), y: .value("Net worth", last.value)).foregroundStyle(c2).symbolSize(80)
                        }
                    }
                    .chartYScale(domain: lo...hi)
                    .chartXAxis(.hidden).chartYAxis(.hidden)
                    .chartXScale(range: .plotDimension(padding: 12)) // room for the end dot and its glow
                    .chartOverlay { proxy in
                        GeometryReader { g in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.12)
                                        .sequenced(before: DragGesture(minimumDistance: 0))
                                        .onChanged { v in if case .second(true, let drag?) = v { pick(drag.location.x, proxy: proxy, geo: g, pts: pts) } }
                                        .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { scrub = nil } }
                                )
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 6)
                                        .onChanged { v in if scrub != nil || abs(v.translation.width) > abs(v.translation.height) { pick(v.location.x, proxy: proxy, geo: g, pts: pts) } }
                                        .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { scrub = nil } }
                                )
                            // the label rides above the dot, laid over the chart (not inside it) so it can be real glass
                            if let s = scrub, let plot = proxy.plotFrame,
                               let px = proxy.position(forX: Month.date(s.month)), let py = proxy.position(forY: s.value) {
                                let o = g[plot].origin
                                ScrubTip(value: Money.format(s.value, store.data.base, decimals: 0), month: Month.short(s.month))
                                    .position(x: min(g.size.width - 58, max(58, o.x + px)), y: max(22, o.y + py - 36))
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .frame(height: 172)
                .mask(alignment: .leading) { GeometryReader { g in Rectangle().frame(width: g.size.width * drawn) } }
                .sensoryFeedback(.selection, trigger: scrub?.month)
                HStack {
                    label(pts.first!)
                    Spacer()
                    label(pts.last!)
                }
                .font(.system(size: 12)).foregroundStyle(Color.sec)
                .padding(.horizontal, 4)
            }
        }
        .onAppear { drawn = 0; withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 1)) { drawn = 1 } }
        .onChange(of: prefs.range) { drawn = 0; withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.9)) { drawn = 1 } }
    }

    private func label(_ p: Store.Point) -> Text {
        Text(Month.short(p.month)) + Text(prefs.hide ? "" : " · " + Money.format(p.value, store.data.base, decimals: 0)).fontWeight(.semibold)
    }

    private func line(_ pts: [Store.Point], lo: Double, hi: Double, c1: Color, c2: Color, width: CGFloat) -> some View {
        Chart(pts) { p in
            LineMark(x: .value("Month", Month.date(p.month)), y: .value("Net worth", p.value))
                .foregroundStyle(LinearGradient(colors: [c1, c2], startPoint: .leading, endPoint: .trailing))
                .lineStyle(StrokeStyle(lineWidth: width, lineCap: .round)).interpolationMethod(.monotone)
        }
        .chartYScale(domain: lo...hi).chartXAxis(.hidden).chartYAxis(.hidden)
                    .chartXScale(range: .plotDimension(padding: 12)) // room for the end dot and its glow
        .allowsHitTesting(false)
    }

    private func pick(_ x: CGFloat, proxy: ChartProxy, geo: GeometryProxy, pts: [Store.Point]) {
        guard let frame = proxy.plotFrame, let date: Date = proxy.value(atX: x - geo[frame].origin.x) else { return }
        let best = pts.min { abs(Month.date($0.month).timeIntervalSince(date)) < abs(Month.date($1.month).timeIntervalSince(date)) }
        if best != scrub { scrub = best }
    }
}

/// 1M · 6M · 1Y · All (a native segmented control).
struct RangePicker: View {
    @Environment(Prefs.self) private var prefs
    var body: some View {
        @Bindable var prefs = prefs
        Picker("Range", selection: $prefs.range) {
            Text("1M").tag(1); Text("6M").tag(6); Text("1Y").tag(12); Text("All").tag(0)
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - add past months

/// "Add past months": until there are 4 months, chips for 1, 3, 6 and 12 months back open a check-in for that month.
struct BackfillCard: View {
    @Environment(Store.self) private var store
    @Environment(Prefs.self) private var prefs
    let open: (String) -> Void

    var body: some View {
        let months = store.backfillMonths
        if !prefs.backfillDone, store.data.snaps.count < 4, !months.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Add past months").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button { withAnimation { prefs.backfillDone = true } } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.sec)
                            .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .accessibilityLabel("Dismiss")
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(months, id: \.self) { m in
                            Button { open(m) } label: {
                                HStack(spacing: 5) { Image(systemName: "plus").font(.system(size: 11, weight: .bold)); Text(store.label(m)) }
                                    .font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
                                    .padding(.horizontal, 12).frame(height: 32)
                                    .background(Capsule().fill(Color.white.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.card))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }
}

// MARK: - empty

struct EmptyState: View {
    @Environment(\.openOnboarding) private var openOnboarding
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill").font(.system(size: 64)).foregroundStyle(Color.g1.gradient)
            Text("Watch your worth grow.").font(.system(size: 22, weight: .bold))
            Text("Every account, home and loan.\nIn any currency.").font(.system(size: 15)).foregroundStyle(Color.sec).multilineTextAlignment(.center)
            Button { openOnboarding() } label: { Text("Get started").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButton()).padding(.top, 8)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }
}

/// The soft green/blue glow behind the top of every tab (the web app's aura). Two blurred blobs are drawn once and
/// then only moved and turned, which the GPU does for free, so the slow drift never costs a re-render.
struct Aura: View {
    @State private var drift = false
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                Color.black
                blob(Color.hex(0x36F5B2).opacity(0.42), w * 1.1)
                    .offset(x: -w * 0.45 + (drift ? 30 : 0), y: -w * 0.55 + (drift ? 20 : -10))
                blob(Color.hex(0x3AA4FF).opacity(0.4), w)
                    .offset(x: w * 0.5 - (drift ? 24 : 0), y: -w * 0.35 + (drift ? -14 : 12))
            }
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { drift = true } }
    }
    /// A blurred blob rendered once into its own layer; moving it afterwards never redraws the blur.
    private func blob(_ c: Color, _ d: CGFloat) -> some View {
        Circle().fill(c).frame(width: d, height: d).padding(120).blur(radius: 90).drawingGroup().padding(-120)
    }
}

/// The label above the scrub dot: amount and month on a glass card, like the web app's tooltip.
private struct ScrubTip: View {
    let value: String
    let month: String
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        let content = VStack(spacing: 1) {
            Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(.white).masked()
            Text(month).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .fixedSize()
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape).overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}
