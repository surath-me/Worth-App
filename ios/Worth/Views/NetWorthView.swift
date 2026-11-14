import SwiftUI
import Charts

/// The main tab: net worth today, the change vs last month, the curve, and every entry by group.
struct NetWorthView: View {
    @Environment(Store.self) private var store
    @State private var editing: Account?
    @State private var adding = false
    @State private var range = 12

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if store.isEmpty { empty } else {
                        hero
                        chart
                        groups
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(aura)
            .navigationTitle("Net worth")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add entry")
                }
            }
            .sheet(item: $editing) { EntrySheet(account: $0) }
            .sheet(isPresented: $adding) { EntrySheet(account: nil) }
        }
    }

    // MARK: parts

    private var hero: some View {
        let total = store.liveTotal, base = store.data.base
        let prev = store.series.dropLast().last
        return VStack(alignment: .leading, spacing: 6) {
            Text("Today").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sec)
            Text(Money.format(total, base, decimals: 0))
                .font(.system(size: 38, weight: .bold)).monospacedDigit()
                .contentTransition(.numericText(value: total))
                .minimumScaleFactor(0.6).lineLimit(1)
            if let prev {
                ChangeLabel(change: total - prev.value, from: prev.value, cur: base, suffix: " vs " + Month.name(prev.month))
            }
            let debts = store.liveDebts
            if debts > 0 {
                Text("Assets \(Money.format(total + debts, base, decimals: 0)) · Debts \(Money.format(debts, base, decimals: 0))")
                    .font(.system(size: 13)).foregroundStyle(Color.sec).monospacedDigit()
            }
        }
        .padding(.top, 4)
    }

    private var chart: some View {
        let all = store.series
        let pts = range == 0 ? all : all.filter { Month.index($0.month) >= Month.index(Month.key()) - range }
        let lo = pts.map(\.value).min() ?? 0, hi = pts.map(\.value).max() ?? 1, pad = max((hi - lo) * 0.15, 1)
        return VStack(spacing: 10) {
            Chart(pts, id: \.month) { p in
                AreaMark(x: .value("Month", Month.date(p.month)), yStart: .value("Low", lo - pad), yEnd: .value("Net worth", p.value))
                    .foregroundStyle(LinearGradient(colors: [Color.g1.opacity(0.35), Color.g2.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Month", Month.date(p.month)), y: .value("Net worth", p.value))
                    .foregroundStyle(LinearGradient(colors: [Color.g1, Color.g2], startPoint: .leading, endPoint: .trailing))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: (lo - pad)...(hi + pad))
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 190)

            Picker("Range", selection: $range) {
                Text("6M").tag(6); Text("1Y").tag(12); Text("All").tag(0)
            }
            .pickerStyle(.segmented)
        }
    }

    private var groups: some View {
        let sp = store.liveSplit
        return VStack(alignment: .leading, spacing: 18) {
            ForEach(Catalog.groups) { g in
                let list = store.accounts(in: g)
                if !list.isEmpty {
                    let v = g.liab ? sp.debts : (sp.groups.first { $0.group.id == g.id }?.value ?? 0)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle().fill(g.color).frame(width: 8, height: 8)
                            Text(g.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sec)
                            Spacer()
                            Text((g.liab ? "−" : "") + Money.format(v, store.data.base, decimals: 0))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sec).monospacedDigit()
                        }
                        .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(list) { a in
                                Button { editing = a } label: { EntryRow(account: a) }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                if a.id != list.last?.id { Divider().padding(.leading, 66) }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                    }
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill").font(.system(size: 64)).foregroundStyle(Color.g1.gradient)
            Text("Watch your worth grow.").font(.system(size: 22, weight: .bold))
            Text("Add your first account, home or loan,\nor restore a backup from the web app in Settings.")
                .font(.system(size: 15)).foregroundStyle(Color.sec).multilineTextAlignment(.center)
            Button { adding = true } label: { Text("Add an entry").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14) }
                .buttonStyle(.borderedProminent).tint(Color.g1).padding(.top, 8)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }

    /// The soft green/blue glow behind the top of the screen, like the web app's aura.
    private var aura: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Color.g1.opacity(0.35), .clear], center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color.g2.opacity(0.3), .clear], center: UnitPoint(x: 0.95, y: 0.05), startRadius: 0, endRadius: 300)
        }
        .ignoresSafeArea()
    }
}
