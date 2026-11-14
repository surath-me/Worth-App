import SwiftUI
import Charts

/// The main tab: net worth today (tap to hide amounts), the change over the chosen range, one plain-language insight,
/// the curve (drag along it to read any month), the "Add past months" card, and the bubbles.
struct NetWorthView: View {
    @Environment(Store.self) private var store
    @Environment(Prefs.self) private var prefs
    @State private var editing: Account?
    @State private var adding: String?          // a type to start a new entry with ("" = default)
    @State private var checkIn: String?         // a month to open the check-in for
    @State private var scrub: Store.Point?      // the month being read on the chart

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.isEmpty { EmptyState() } else {
                        hero.padding(.top, 2)
                        WorthChart(scrub: $scrub).padding(.top, 14)
                        RangePicker().padding(.top, 12)
                        BackfillCard { checkIn = $0 }.padding(.top, 16)
                        if store.data.accounts.contains(where: { store.conv($0.bal, $0.cur) > 0 }) {
                            Text("Breakdown").sectionLabel().padding(.top, 24)
                            Bubbles(onOpen: { editing = $0 }, onAdd: { adding = $0 })
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDisabled(scrub != nil)
            .background(Aura())
            .navigationTitle("Net worth")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = "" } label: { Image(systemName: "plus") }.accessibilityLabel("Add entry")
                }
            }
            .sheet(item: $editing) { EntrySheet(account: $0) }
            .sheet(item: Binding(get: { adding.map(TypeChoice.init) }, set: { adding = $0?.id })) { EntrySheet(account: nil, startType: $0.id.isEmpty ? nil : $0.id) }
            .sheet(item: Binding(get: { checkIn.map(TypeChoice.init) }, set: { checkIn = $0?.id })) { CheckInSheet(start: $0.id) }
        }
    }

    // MARK: hero

    private var hero: some View {
        let total = scrub?.value ?? store.liveTotal, base = store.data.base
        let pts = store.points(range: prefs.range)
        let ref = pts.first { $0.month != Month.key() }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(scrub.map { Month.long($0.month) } ?? "Today").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sec)
                Button { prefs.hide.toggle() } label: {
                    Image(systemName: prefs.hide ? "eye.slash.fill" : "eye.fill").font(.system(size: 12)).foregroundStyle(Color.sec)
                }
                .accessibilityLabel(prefs.hide ? "Show amounts" : "Hide amounts")
            }
            Text(Money.format(total, base, decimals: 0))
                .font(.system(size: 38, weight: .bold)).monospacedDigit()
                .contentTransition(.numericText(value: total))
                .animation(.snappy(duration: 0.25), value: total)
                .minimumScaleFactor(0.6).lineLimit(1)
                .masked()
                .onTapGesture { prefs.hide.toggle() }
            delta(total: total, pts: pts, ref: ref)
            if scrub == nil {
                let ins = store.insight(total: total, ref: ref)
                if ins.badge != nil || ins.move != nil {
                    (Text(ins.badge ?? "").fontWeight(.semibold).foregroundStyle(.white)
                     + Text(ins.badge != nil && ins.move != nil ? " · " : "")
                     + Text(ins.move ?? ""))
                        .font(.system(size: 13)).foregroundStyle(Color.sec).masked()
                        .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder private func delta(total: Double, pts: [Store.Point], ref: Store.Point?) -> some View {
        if let scrub {
            if let first = pts.first, first.month != scrub.month {
                ChangeLabel(change: scrub.value - first.value, from: first.value, cur: store.data.base, suffix: "  since " + Month.short(first.month)).masked()
            } else { Text("Start of range").font(.system(size: 15)).foregroundStyle(Color.sec) }
        } else if let ref, let first = pts.first {
            ChangeLabel(change: total - first.value, from: first.value, cur: store.data.base, suffix: "  " + store.rangeLabel(ref: ref, range: prefs.range)).masked()
        } else if !store.data.accounts.isEmpty {
            Text("First month").font(.system(size: 15)).foregroundStyle(Color.sec)
        }
    }
}

/// Lets a String drive `.sheet(item:)`.
struct TypeChoice: Identifiable { let id: String }

// MARK: - chart

/// The curve: green→blue when up over the range, red→orange when down. Drag along it to read any month; the hero follows.
struct WorthChart: View {
    @Environment(Store.self) private var store
    @Environment(Prefs.self) private var prefs
    @Binding var scrub: Store.Point?
    @State private var drawn: CGFloat = 0

    var body: some View {
        let pts = store.points(range: prefs.range)
        let up = pts.count < 2 || pts.last!.value >= pts.first!.value
        let c1 = up ? Color.g1 : Color.hex(0xFF4D6A), c2 = up ? Color.hex(0x3AA4FF) : Color.hex(0xFF9F0A)
        let vs = pts.map(\.value)
        let lo0 = vs.min() ?? 0, hi0 = vs.max() ?? 1
        let span = max(hi0 - lo0, max(1, abs(hi0) * 0.04)), lo = lo0 - span * 0.14, hi = hi0 + span * 0.14
        VStack(spacing: 6) {
            if pts.count < 2 {
                Text(pts.isEmpty ? "No data in this range" : "One month so far")
                    .font(.system(size: 13)).foregroundStyle(Color.sec).frame(maxWidth: .infinity, minHeight: 170)
            } else {
                Chart {
                    RuleMark(y: .value("Start", pts[0].value))
                        .foregroundStyle(.white.opacity(0.12)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    ForEach(pts) { p in
                        AreaMark(x: .value("Month", Month.date(p.month)), yStart: .value("Low", lo), yEnd: .value("Net worth", p.value))
                            .foregroundStyle(LinearGradient(colors: [c2.opacity(0.26), c1.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Month", Month.date(p.month)), y: .value("Net worth", p.value))
                            .foregroundStyle(LinearGradient(colors: [c1, c2], startPoint: .leading, endPoint: .trailing))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                    if let s = scrub {
                        RuleMark(x: .value("Month", Month.date(s.month))).foregroundStyle(.white.opacity(0.25))
                        PointMark(x: .value("Month", Month.date(s.month)), y: .value("Net worth", s.value))
                            .foregroundStyle(c2).symbolSize(110)
                    } else if let last = pts.last {
                        PointMark(x: .value("Month", Month.date(last.month)), y: .value("Net worth", last.value))
                            .foregroundStyle(c2).symbolSize(70)
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 170)
                .mask(alignment: .leading) { GeometryReader { g in Rectangle().frame(width: g.size.width * drawn) } }
                .chartOverlay { proxy in
                    GeometryReader { g in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                LongPressGesture(minimumDuration: 0.12)
                                    .sequenced(before: DragGesture(minimumDistance: 0))
                                    .onChanged { v in
                                        if case .second(true, let drag?) = v { pick(drag.location.x, proxy: proxy, geo: g, pts: pts) }
                                    }
                                    .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { scrub = nil } }
                            )
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 6)
                                    .onChanged { v in
                                        if scrub != nil || abs(v.translation.width) > abs(v.translation.height) { pick(v.location.x, proxy: proxy, geo: g, pts: pts) }
                                    }
                                    .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { scrub = nil } }
                            )
                    }
                }
                .sensoryFeedback(.selection, trigger: scrub?.month)
                HStack {
                    Text(Month.short(pts.first!.month)) + Text(prefs.hide ? "" : " · " + Money.format(pts.first!.value, store.data.base, decimals: 0))
                    Spacer()
                    Text(Month.short(pts.last!.month)) + Text(prefs.hide ? "" : " · " + Money.format(pts.last!.value, store.data.base, decimals: 0))
                }
                .font(.system(size: 12)).foregroundStyle(Color.sec)
            }
        }
        .onAppear { drawn = 0; withAnimation(.easeInOut(duration: 1)) { drawn = 1 } }
        .onChange(of: prefs.range) { drawn = 0; withAnimation(.easeInOut(duration: 0.9)) { drawn = 1 } }
    }

    private func pick(_ x: CGFloat, proxy: ChartProxy, geo: GeometryProxy, pts: [Store.Point]) {
        guard let frame = proxy.plotFrame, let date: Date = proxy.value(atX: x - geo[frame].origin.x) else { return }
        let best = pts.min { abs(Month.date($0.month).timeIntervalSince(date)) < abs(Month.date($1.month).timeIntervalSince(date)) }
        if best != scrub { scrub = best }
    }
}

/// 1M · 6M · 1Y · All
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
                HStack(spacing: 8) {
                    ForEach(months, id: \.self) { m in
                        Button { open(m) } label: {
                            Label(store.label(m), systemImage: "plus").font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12).frame(height: 32)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
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

/// The soft green/blue glow behind the top of every tab, like the web app's aura.
struct Aura: View {
    @State private var drift = false
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Color.hex(0x36F5B2).opacity(0.28), .clear], center: UnitPoint(x: drift ? 0.2 : 0.05, y: 0), startRadius: 0, endRadius: 340)
            RadialGradient(colors: [Color.hex(0x3AA4FF).opacity(0.26), .clear], center: UnitPoint(x: drift ? 0.85 : 1, y: drift ? 0.08 : 0.02), startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true } }
    }
}
